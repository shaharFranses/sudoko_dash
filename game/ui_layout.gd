## Mobile / responsive layout rules (pure logic, unit-tested in tests/test_mobile_layout.gd).
## The game is laid out in "logical units" (Godot canvas_items stretch). Desktop and tablet landscape keep
## the original 1280x720 base (unchanged look). Portrait pages (phones, tablets) use a 720-unit-wide base
## (the art kit's portrait base: harbour_bg_portrait is 720x1280, ArtPalette.MIN_TOUCH = 88 at 720 wide),
## so an 88-unit button is >= 44 CSS px even on a 360 px phone. Short landscape (phones held sideways)
## gets a logical height of 480 so 56-unit buttons are >= 44 CSS px.
extends RefCounted

const DESKTOP_BASE = Vector2(1280, 720)
const DESKTOP_MIN_H = 600.0       # landscape pages at least this tall (CSS px) keep the desktop base
const PORTRAIT_BASE_W = 720.0     # portrait: logical width 720 on phones (360 CSS px -> 0.5 CSS px/unit)
const PORTRAIT_MIN_ASPECT = 1.75  # squatter portrait pages (tablets) get a wider base so the column still fits
const LANDSCAPE_MIN_H = 480.0     # short landscape (phones): logical height never below this
const MIN_TOUCH_CSS = 44.0        # minimum touch target, CSS px
const COMPACT_MIN_BTN = 88        # minimum touch size in compact (portrait) layout = ArtPalette.MIN_TOUCH
const COMPACT_SCALE = 720.0 / 420.0   # compact layout sizes are authored for 420 wide, scaled to the 720 base

## Logical viewport for a page of `css` CSS px. Vector2.ZERO = keep the desktop base (1280x720, expand).
static func logical_size(css: Vector2) -> Vector2:
	if css.x <= 0.0 or css.y <= 0.0: return Vector2.ZERO
	if css.x >= css.y:
		if css.y >= DESKTOP_MIN_H: return Vector2.ZERO
		var k = maxf(1.0, LANDSCAPE_MIN_H / css.y)
		return (css * k).round()
	var k = PORTRAIT_BASE_W / css.x * maxf(1.0, PORTRAIT_MIN_ASPECT / (css.y / css.x))
	return (css * k).round()

## Logical units per CSS px for a page of `css` CSS px (inverse of the on-screen size of one unit).
static func units_per_css(css: Vector2) -> float:
	var ls = logical_size(css)
	if ls == Vector2.ZERO:
		if css.x <= 0.0 or css.y <= 0.0: return 1.0
		return 1.0 / minf(css.x / DESKTOP_BASE.x, css.y / DESKTOP_BASE.y)
	return ls.x / css.x

## Portrait (taller than wide) logical viewports use the compact one-column layout.
static func is_compact(vp: Vector2) -> bool:
	return vp.y > vp.x

## Digit pad columns. Compact: 6x6 -> one row of 6; 9x9 -> 5 columns (1-9 + Erase in two rows).
static func pad_columns(n: int, compact: bool) -> int:
	if compact: return n if n <= 6 else 5
	return 3 if n == 9 or n == 6 else 2
