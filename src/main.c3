module dashboard;
import cui;
import std::math;

fn void push_stats(Ui* ui)
{
	SystemStats s = sample_stats();
	ui.@modify_id("cpu", StatCard; c) { c.value = s.cpu; };
	ui.@modify_id("mem", StatCard; c) { c.value = s.mem; };
	ui.@modify_id("disk", StatCard; c) { c.value = s.disk; };
}

fn void reset_limit(Ui* ui)
{
	ui.@modify(LimitDial; d) { d.value = DEFAULT_LIMIT; };
	apply_limit(ui, DEFAULT_LIMIT);
}

fn void main(String[] args)
{
	Vec2 window_size = { WIN_W, WIN_H };

	// CONTINUOUS: the stat sampler below must tick every second even with no
	// input, and in ON_DEMAND mode frame() parks until an event arrives. (A
	// UI that only changes on interaction would want ON_DEMAND.)
	Renderer renderer = cui::vulkan::new(window_size: window_size, loop_mode: CONTINUOUS)!!;
	defer catch renderer.free();

	// Baseline for the first CPU delta; the first sample lands ~1/4 s in.
	stats_prime();
	SystemStats stats = sample_stats();

	// Load images before building the tree — the styles below bake the
	// returned texture handles in.
	Texture banner = renderer.load_image("resources/banner.png")!!;
	Texture logo   = renderer.load_image("resources/logo.png")!!;

	Ui* ui = cui::new_ui(window_size);
	defer ui.free();

	// First loaded font is FontId 0 — every Label and TextStyle in the app
	// leaves .font unset and gets it.
	ui.load_font("resources/DejaVuSans.ttf")!!;

	@canvas(ui)
	{
		@tree((Stack) { }) // size 0 = fill the window
		{
			@node((Rectangle) { .size = { WIN_W, WIN_H }, .style = { .color = BG } });
			@tree((Padding) { .insets = widgets::insets_all(PAD) })
			{
				@tree((Column) { .gap = 16.0 })
				{
					// ---- header: banner texture, text over it, round logo ----
					@tree((Stack) { .size = { CONTENT_W, HEADER_H } })
					{
						@node(
							(Rectangle) {
								.size = { CONTENT_W, HEADER_H },
								.style = { .texture = banner, .border_radius = R14 },
							}
						);
						@node((Label) { .text = "Mission Control", .size = 30.0, .color = TEXT })
							.set_offset({ 28.0, 26.0 });
						@node((Label) { .text = "a tiny dashboard built with cui", .size = 14.0, .color = TEXT_DIM })
							.set_offset({ 28.0, 66.0 });
						@node(
							(Rectangle) {
								.size = { 56.0, 56.0 },
								.style = { .texture = logo, .border_radius = { 28.0, 28.0, 28.0, 28.0 } },
							}
						).set_offset({ CONTENT_W - 84.0, 27.0 });
					};
					// ---- stat cards; ids let the dial and sampler find each ----
					// Clicking a card resamples immediately (the loop below
					// refreshes every second anyway).
					@tree((Row) { .size = { CONTENT_W, 0 }, .gap = 16.0 })
					{
						@node((StatCard) { .title = "CPU", .value = stats.cpu, .limit = DEFAULT_LIMIT,
							.accent = ACCENT_BLUE, .on_click = &push_stats }).with_id("cpu");
						@node((StatCard) { .title = "MEMORY", .value = stats.mem, .limit = DEFAULT_LIMIT,
							.accent = ACCENT, .on_click = &push_stats }).with_id("mem");
						@node((StatCard) { .title = "DISK", .value = stats.disk, .limit = DEFAULT_LIMIT,
							.accent = ACCENT_GREEN, .on_click = &push_stats }).with_id("disk");
					};
					// ---- bottom: scrolling log | settings panel ----
					@tree((Row) { .size = { CONTENT_W, 0 }, .gap = 16.0 })
					{
						@node((ActivityLog) { .size = { LOG_W, PANEL_H } });
						@tree((Stack) { .size = { SIDE_W, PANEL_H } })
						{
							@node(
								(Rectangle) {
									.size = { SIDE_W, PANEL_H },
									.style = {
										.color = PANEL,
										.border_radius = R14,
										.border_width = 1.0,
										.border_color = PANEL_BORDER,
									},
								}
							);
							@tree((Padding) { .insets = widgets::insets_all(16.0) })
							{
								@tree((Column) { .gap = 12.0, .size = { SIDE_W - 32.0, 0 }, .cross_align = CENTER })
								{
									@node((Label) { .text = "LIMIT", .size = 13.0, .color = TEXT_DIM });
									@node((LimitDial) { .size = { 190.0, 190.0 }, .value = DEFAULT_LIMIT });
									@node(
										(TextButton) {
											.text = "Reset",
											.size = { 140.0, 38.0 },
											.text_size = 15.0,
											.style = { .color = { 0.20, 0.22, 0.28, 1.0 }, .border_radius = { 10.0, 10.0, 10.0, 10.0 } },
											.hover_style = { .color = { 0.28, 0.31, 0.40, 1.0 }, .border_radius = { 10.0, 10.0, 10.0, 10.0 } },
											.press_style = { .color = { 0.16, 0.17, 0.22, 1.0 }, .border_radius = { 10.0, 10.0, 10.0, 10.0 } },
											.on_click = &reset_limit,
										}
									);
								};
							};
						};
					};
				};
			};
		};
	};

	// The app owns the loop: frame() polls input, dispatches to the widgets,
	// flushes and presents; the body is the per-frame hook. Here it refreshes
	// the cards from the live system stats once a second.
	float since_sample = 0.75f; // first sample ~1/4 s in, for a real CPU delta
	while (renderer.frame(ui)!!)
	{
		since_sample += ui.input.dt;
		if (since_sample >= 1.0f)
		{
			since_sample = 0;
			push_stats(ui);
		}
	}
}
