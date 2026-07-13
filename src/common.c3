module dashboard;
import cui;
import std::math;

// Shared palette and dimensions, plus TextButton — a custom leaf widget with
// hover/press states and centered text. (A Label child of a Button would
// steal the hover: on_hover goes only to the deepest hit element, it does
// not bubble like on_mouse. A self-painting leaf sidesteps that.)

// ---- palette (linear RGBA 0..1) ----
const Color BG           = { 0.09, 0.10, 0.13, 1.0 };
const Color PANEL        = { 0.16, 0.17, 0.22, 1.0 };
const Color PANEL_BORDER = { 0.28, 0.30, 0.38, 1.0 };
const Color TRACK        = { 0.24, 0.26, 0.32, 1.0 };
const Color TEXT         = { 0.92, 0.93, 0.95, 1.0 };
const Color TEXT_DIM     = { 0.55, 0.58, 0.66, 1.0 };
const Color ACCENT       = { 0.95, 0.60, 0.20, 1.0 };
const Color ACCENT_BLUE  = { 0.35, 0.70, 0.95, 1.0 };
const Color ACCENT_GREEN = { 0.55, 0.85, 0.45, 1.0 };
const Color DANGER       = { 0.92, 0.30, 0.26, 1.0 };
const Vec4  R14          = { 14.0, 14.0, 14.0, 14.0 };

// ---- dimensions (see README: everything sums to the 900x640 window) ----
const float WIN_W     = 900.0;
const float WIN_H     = 640.0;
const float PAD       = 20.0;
const float CONTENT_W = WIN_W - 2 * PAD;
const float HEADER_H  = 110.0;
const float CARD_W    = 276.0;
const float CARD_H    = 96.0;
const float LOG_W     = 584.0;
const float SIDE_W    = 260.0;
const float PANEL_H   = 362.0;

const float DEFAULT_LIMIT = 0.65;

struct TextButton (Widget)
{
	String text; // borrowed; must outlive the element (a literal is ideal)
	Vec2 size;
	float text_size; // 0 uses cui::DEFAULT_TEXT_SIZE
	RectStyle style;
	RectStyle hover_style; // used while hovered, if its color alpha > 0
	RectStyle press_style; // used while held, if its color alpha > 0
	OnClick on_click; // optional; called on click-release inside
	bool hovered;
	bool held;
}

fn Vec2 TextButton.layout(&self, Element* elem, Constraints constraints) @dynamic
{
	elem.cursor = Cursor.POINTING_HAND;
	return self.size.constrain(constraints);
}

fn void TextButton.paint(&self, Element* elem, Painter* painter) @dynamic
{
	RectStyle style = self.style;
	if (self.held && ((Vec4)self.press_style.color).w > 0)
	{
		style = self.press_style;
	}
	else if (self.hovered && ((Vec4)self.hover_style.color).w > 0)
	{
		style = self.hover_style;
	}
	painter.rect({ 0, 0 }, elem.size, style);

	Vec2 ts = elem.ui.text.measure(0, self.text, self.text_size);
	painter.text(
		{ (elem.size.x - ts.x) * 0.5f, (elem.size.y - ts.y) * 0.5f },
		self.text,
		{ .size = self.text_size, .color = TEXT }
	);
}

fn void TextButton.on_hover(&self, Element* elem, bool entered) @dynamic
{
	self.hovered = entered;
	elem.request_paint();
}

fn bool TextButton.on_mouse(&self, Element* elem, MouseEvent event) @dynamic
{
	switch (event.kind)
	{
		case PRESS:
			if (event.button != MouseButton.LEFT) return false;
			self.held = true;
			elem.request_paint();
			return true; // consuming the press captures the pointer
		case RELEASE:
			if (event.button != MouseButton.LEFT || !self.held) return false;
			self.held = false;
			elem.request_paint();
			bool inside = event.pos.x >= 0 && event.pos.y >= 0 && event.pos.x < elem.size.x
				&& event.pos.y < elem.size.y;
			if (inside && self.on_click) self.on_click(elem.ui);
			return true;
		default:
			return false;
	}
}
