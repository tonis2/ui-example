module dashboard;
import cui;
import std::math;

// The activity log: static fake data plus a second composite widget —
// ActivityLog wraps a Scroll around a Column of entry rows. The content
// (~570 px) overflows the 362 px viewport, so the wheel scrolls it and the
// proportional thumb appears at the right edge.

enum LogStatus
{
	OK,
	WARN,
	FAIL,
}

struct LogEntry
{
	String time;
	String msg;
	LogStatus status;
}

LogEntry[] log_entries = {
	{ "09:12", "Deploy pipeline finished", OK },
	{ "09:14", "Cache hit ratio 96.2%", OK },
	{ "09:18", "Worker 3 restarted", WARN },
	{ "09:21", "TLS certificate renewed", OK },
	{ "09:26", "Disk latency spike on /dev/d1", WARN },
	{ "09:30", "Nightly backup completed", OK },
	{ "09:33", "Replica lag exceeded 5s", FAIL },
	{ "09:35", "Replica caught up", OK },
	{ "09:41", "Autoscaler added 2 nodes", OK },
	{ "09:47", "Memory pressure on worker 1", WARN },
	{ "09:52", "Job queue drained", OK },
	{ "09:58", "Healthcheck timeout: api-7", FAIL },
	{ "10:01", "api-7 recovered after restart", OK },
	{ "10:07", "Config rollout 42% complete", OK },
	{ "10:12", "Rate limiter engaged for /search", WARN },
	{ "10:19", "Config rollout complete", OK },
	{ "10:24", "CDN purge finished in 1.8s", OK },
	{ "10:31", "All systems nominal", OK },
};

fn Color status_color(LogStatus s)
{
	switch (s)
	{
		case OK: return ACCENT_GREEN;
		case WARN: return ACCENT;
		case FAIL: return DANGER;
	}
}

struct ActivityLog (Widget)
{
	Vec2 size;
}

fn Element* ActivityLog.build(&self, Element* elem) @dynamic
{
	float row_w = self.size.x - 32.0f - 12.0f; // insets + scrollbar clearance
	return @subtree(elem.ui)
	{
		@tree((Stack) { .size = self.size })
		{
			@node(
				(Rectangle) {
					.size = self.size,
					.style = {
						.color = PANEL,
						.border_radius = R14,
						.border_width = 1.0,
						.border_color = PANEL_BORDER,
					},
				}
			);
			// A Scroll takes exactly one node child: the content to scroll.
			@tree((Scroll) { .size = self.size, .radii = R14 })
			{
				@tree((Padding) { .insets = { .left = 16.0, .top = 14.0, .right = 16.0, .bottom = 14.0 } })
				{
					@tree((Column) { .gap = 10.0 })
					{
						@node((Label) { .text = "ACTIVITY", .size = 13.0, .color = TEXT_DIM });
						foreach (entry : log_entries)
						{
							@node(
								(Row) { .size = { row_w, 0 }, .gap = 10.0, .cross_align = CENTER },
								(Label) { .text = entry.time, .size = 13.0, .color = TEXT_DIM },
								(Rectangle) {
									.size = { 8.0, 8.0 },
									.style = { .color = status_color(entry.status), .border_radius = { 4.0, 4.0, 4.0, 4.0 } },
								},
								(Label) { .text = entry.msg, .size = 14.0, .color = TEXT }
							);
						}
					};
				};
			};
		};
	};
}
