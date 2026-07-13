module dashboard;
import cui;
import std::math;

// A custom widget painting with the Painter primitives directly — circle,
// line, arc, rect_shadow and text. A gauge for the shared "limit": drag or
// scroll on it to set the value, click to focus it, then nudge with the
// arrow keys. Every change is pushed to the three StatCards via
// apply_limit, so the cards recolor live while you drag.

struct LimitDial (Widget)
{
	Vec2 size;
	float value; // 0..1 — the shared limit threshold
	bool dragging; // between PRESS and RELEASE on this widget
	char[8] pct_buf; // backing store for the center readout
}

// The gauge spans 3/4 of a turn, opening at the bottom. Angles: 0 = +x,
// clockwise on screen.
const float DIAL_START = 0.75 * math::PI;
const float DIAL_SPAN  = 1.5 * math::PI;

// One tree walk per card: mutate the limit, and because StatCard is a build
// widget, @modify_id's request_paint routes to request_build — each card
// regenerates with the new limit on the next flush.
fn void apply_limit(Ui* ui, float limit)
{
	ui.@modify_id("cpu", StatCard; c) { c.limit = limit; };
	ui.@modify_id("mem", StatCard; c) { c.limit = limit; };
	ui.@modify_id("disk", StatCard; c) { c.limit = limit; };
}

fn Vec2 LimitDial.layout(&self, Element* elem, Constraints constraints) @dynamic
{
	elem.cursor = Cursor.OPEN_HAND;
	return self.size.constrain(constraints);
}

// Point the needle at the pointer: angle of the element-local position
// around the center, mapped into the gauge's arc.
fn void LimitDial.drag(&self, Element* elem, Vec2 local)
{
	Vec2 d    = local - elem.size * 0.5f;
	float rel = math::atan2(d.y, d.x) - DIAL_START;
	while (rel < 0) rel += 2.0f * (float)math::PI;
	if (rel > DIAL_SPAN)
	{
		// The dead zone at the bottom: snap to the closer end.
		self.value = rel - DIAL_SPAN > 0.25f * (float)math::PI ? 0.0f : 1.0f;
	}
	else
	{
		self.value = rel / DIAL_SPAN;
	}
	elem.request_paint();
	apply_limit(elem.ui, self.value);
}

fn bool LimitDial.on_mouse(&self, Element* elem, MouseEvent event) @dynamic
{
	switch (event.kind)
	{
		case PRESS:
			if (event.button != MouseButton.LEFT) return false;
			self.dragging = true;
			self.drag(elem, event.pos);
			return true; // consuming the press captures the drag
		case MOVE:
			// Only drag between our own PRESS and RELEASE — a button held
			// down elsewhere must not steer the dial as the pointer passes.
			if (!self.dragging) return false;
			self.drag(elem, event.pos);
			return true;
		case RELEASE:
			if (event.button != MouseButton.LEFT || !self.dragging) return false;
			self.dragging = false;
			return true;
		case SCROLL:
			self.value = math::clamp(self.value + event.scroll * 0.005f, 0.0f, 1.0f);
			elem.request_paint();
			apply_limit(elem.ui, self.value);
			return true;
		default:
			return false;
	}
}

// Clicking the dial focuses it (it implements on_key); arrows nudge it.
fn bool LimitDial.on_key(&self, Element* elem, KeyEvent event) @dynamic
{
	if (!event.down) return false;
	switch (event.key)
	{
		case Key.LEFT_ARROW: self.value = math::clamp(self.value - 0.05f, 0.0f, 1.0f);
		case Key.RIGHT_ARROW: self.value = math::clamp(self.value + 0.05f, 0.0f, 1.0f);
		default: return false;
	}
	elem.request_paint();
	apply_limit(elem.ui, self.value);
	return true;
}

fn void LimitDial.paint(&self, Element* elem, Painter* painter) @dynamic
{
	Vec2 center  = elem.size * 0.5f;
	float radius = math::min(elem.size.x, elem.size.y) * 0.5f - 16.0f;

	float start = DIAL_START;
	float span  = DIAL_SPAN;

	// Soft circular glow behind the face — a shadow is just a blurred rect,
	// and full-corner radii make it round.
	painter.rect_shadow(
		{ center.x - radius, center.y - radius },
		{ radius * 2.0f, radius * 2.0f },
		26.0f,
		{ 0.95, 0.60, 0.20, 0.35 },
		{ radius, radius, radius, radius }
	);

	painter.circle(
		center,
		radius,
		{ .color = { 0.13, 0.15, 0.19, 1.0 }, .border_width = 2.0f, .border_color = { 0.32, 0.35, 0.42, 1.0 }, }
	);

	// Tick lines around the rim.
	for (int i = 0; i <= 10; i++)
	{
		float angle = start + span * (float)i / 10.0f;
		Vec2 dir    = { math::cos(angle), math::sin(angle) };
		painter.line(center + dir * (radius - 16.0f), center + dir * (radius - 8.0f), 2.0f, { 0.45, 0.48, 0.56, 1.0 });
	}

	// Track arc, then the value arc over it.
	painter.arc(center, radius - 28.0f, start, span, 7.0f, TRACK);
	painter.arc(center, radius - 28.0f, start, span * self.value, 7.0f, ACCENT);

	// Needle and hub.
	float needle_angle = start + span * self.value;
	Vec2 dir           = { math::cos(needle_angle), math::sin(needle_angle) };
	painter.line(center, center + dir * (radius - 34.0f), 3.0f, cui::WHITE);
	painter.circle(center, 7.0f, { .color = ACCENT });

	// Percentage readout in the gauge's bottom opening — Painter.text from a
	// custom paint, the same call Label uses.
	String txt = string::bformat(self.pct_buf[..], "%d%%", (int)(self.value * 100.0f + 0.5f));
	Vec2 ts    = elem.ui.text.measure(0, txt, 20.0);
	painter.text(
		{ center.x - ts.x * 0.5f, center.y + radius * 0.45f },
		txt,
		{ .size = 20.0, .color = TEXT }
	);
}
