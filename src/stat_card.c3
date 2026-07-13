module dashboard;
import cui;
import std::math;

// A composite widget: its look is COMPOSED from built-in widgets in build()
// rather than painted. The card shows a title, a percentage and a progress
// bar; everything over the shared limit turns red. Clicking it fires
// on_click (wired to a randomizer in main.c3), hovering tints it.
//
// The hover/click surface is a transparent Button overlay as the topmost
// Stack child: on_hover is delivered only to the deepest hit element (it
// does not bubble), so the composite itself would never see it — the Button
// does, and handles hover/press as a cheap leaf repaint with no rebuild.

const float CARD_PAD = 16.0;
const float BAR_W    = CARD_W - 2.0 * CARD_PAD;

struct StatCard (Widget)
{
	String title; // borrowed; a literal is ideal
	float value; // 0..1, drives the progress fill
	float limit; // 0..1, set live by the LimitDial via apply_limit
	Color accent; // bar color while under the limit
	OnClick on_click; // forwarded to the overlay Button
	char[8] pct_buf; // backing store for the "NN%" label; the composite
	// widget (and this buffer) survives rebuilds of its subtree
}

fn Element* StatCard.build(&self, Element* elem) @dynamic
{
	bool over    = self.value > self.limit;
	Color fill_c = over ? DANGER : self.accent;
	float fill   = math::clamp(self.value, 0.0f, 1.0f) * BAR_W;
	String pct   = string::bformat(self.pct_buf[..], "%d%%", (int)(self.value * 100.0f + 0.5f));

	return @subtree(elem.ui)
	{
		@tree((Stack) { .size = { CARD_W, CARD_H } })
		{
			// Background panel; the border warns when over the limit.
			@node(
				(Rectangle) {
					.size = { CARD_W, CARD_H },
					.style = {
						.color = PANEL,
						.border_radius = R14,
						.border_width = 1.0,
						.border_color = over ? DANGER : PANEL_BORDER,
					},
				}
			);
			@tree((Padding) { .insets = widgets::insets_all(CARD_PAD) })
			{
				@tree((Column) { .gap = 14.0 })
				{
					@node(
						(Row) { .size = { BAR_W, 0 }, .main_align = SPACE_BETWEEN, .cross_align = CENTER },
						(Label) { .text = self.title, .size = 14.0, .color = TEXT_DIM },
						(Label) { .text = pct, .size = 16.0, .color = over ? DANGER : TEXT }
					);
					// Progress bar: fill + remainder side by side, summing to BAR_W.
					@node(
						(Row) { .size = { BAR_W, 12.0 } },
						(Rectangle) {
							.size = { fill, 12.0 },
							.style = { .color = fill_c, .border_radius = { 6.0, 0.0, 0.0, 6.0 } },
						},
						(Rectangle) {
							.size = { BAR_W - fill, 12.0 },
							.style = { .color = TRACK, .border_radius = { 0.0, 6.0, 6.0, 0.0 } },
						}
					);
				};
			};
			// Topmost: the transparent interaction overlay (hover tint, press
			// tint, hand cursor, click callback).
			@node(
				(Button) {
					.size = { CARD_W, CARD_H },
					.style = { .border_radius = R14 }, // alpha 0 = invisible
					.hover_style = { .color = { 1.0, 1.0, 1.0, 0.05 }, .border_radius = R14 },
					.press_style = { .color = { 1.0, 1.0, 1.0, 0.10 }, .border_radius = R14 },
					.on_click = self.on_click,
				}
			);
		};
	};
}
