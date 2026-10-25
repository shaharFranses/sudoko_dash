## Harbour scene (art kit v1): painted village background + one sprite per task, unrestored until the task is
## bought, restored after (with a gentle cross-fade the first time it is seen). Layout-agnostic: fills whatever
## rect the Harbour screen gives it.
##
## Background: portrait (720x1280) or landscape (1280x720) art, picked by this view's aspect, cover-cropped.
## The crop is centred on the task sprites; if a very wide/short rect can't show every sprite while covering,
## the view zooms out just enough and fills the edge with a mirrored copy of the art (no sprite is ever cut).
extends Control

const AP = preload("res://assets/art/art_palette.gd")
const BG = {
	"portrait": preload("res://assets/art/harbour/harbour_bg_portrait.webp"),
	"landscape": preload("res://assets/art/harbour/harbour_bg_landscape.webp"),
}
## Sprite placement in background pixels: foot = bottom-centre point, w = drawn width (both states).
## Mirrored in assets/art/harbour/harbour_layout_portrait.json (v2, for art tools); this table is what the game uses.
const LAYOUT = {
	"portrait": {
		"lighthouse": {"foot": Vector2(592, 470), "w": 66.0},
		"boats": {"foot": Vector2(560, 768), "w": 220.0},
		"dock": {"foot": Vector2(332, 842), "w": 150.0},
		"cafe": {"foot": Vector2(122, 805), "w": 240.0},
		"flowers": {"foot": Vector2(236, 892), "w": 170.0},
	},
	"landscape": {
		"lighthouse": {"foot": Vector2(1036, 262), "w": 66.0},
		"boats": {"foot": Vector2(770, 560), "w": 230.0},
		"dock": {"foot": Vector2(452, 630), "w": 140.0},
		"cafe": {"foot": Vector2(132, 610), "w": 250.0},
		"flowers": {"foot": Vector2(340, 698), "w": 170.0},
	},
}
## Decor choices beyond the first: a gentle tint on the restored sprite (dedicated decor art is an art-kit v2 item).
const DECOR_TINT = {
	"dock": [Color(1, 1, 1), Color(0.82, 0.9, 1.08), Color(1.05, 0.95, 0.85)],
	"boats": [Color(1, 1, 1), Color(0.8, 1.05, 0.95), Color(1.1, 1.05, 0.75)],
	"flowers": [Color(1, 1, 1), Color(0.9, 0.85, 1.12)],
	"lighthouse": [Color(1, 1, 1), Color(0.85, 0.92, 1.1), Color(1.05, 1.05, 1.05)],
	"cafe": [Color(1, 1, 1), Color(1.05, 1.0, 0.88)],
}
const REVEAL_S = 1.1

var profile = null
var reveal_id: String = ""      # task restored this visit: its restored sprite fades in once
var _reveal_t: float = 0.0
var _tex: Dictionary = {}

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(reveal_id != "")
	resized.connect(queue_redraw)

func _process(delta: float) -> void:
	_reveal_t += delta
	if _reveal_t >= REVEAL_S:
		reveal_id = ""
		set_process(false)
	queue_redraw()

func _sprite(id: String, restored: bool) -> Texture2D:
	var k = id + ("_r" if restored else "_u")
	if not _tex.has(k): _tex[k] = load(AP.task_sprite_path(id, restored))
	return _tex[k]

## Which sprite a task shows right now (tests / QA).
func state_of(id: String) -> String:
	return "restored" if profile and profile.tasks.has(id) else "unrestored"

## "portrait" or "landscape" art for a rect of this size.
static func pick(sz: Vector2) -> String:
	return "landscape" if sz.x >= sz.y * 1.35 else "portrait"

func _rect_of(id: String, lay: Dictionary, restored: bool) -> Rect2:
	var t = _sprite(id, restored)
	var w: float = lay[id].w
	var h = w * t.get_height() / float(t.get_width())
	return Rect2(lay[id].foot - Vector2(w / 2.0, h), Vector2(w, h))

## Scale + offset mapping background pixels to this control (also used by tests / QA).
func view_transform() -> Dictionary:
	var kind = pick(size)
	var img: Vector2 = BG[kind].get_size()
	var lay: Dictionary = LAYOUT[kind]
	var bb = Rect2()
	var first = true
	for id in lay:
		for st in [false, true]:
			var r = _rect_of(id, lay, st)
			bb = r if first else bb.merge(r)
			first = false
	bb = bb.grow(16)
	var s_cover = maxf(size.x / img.x, size.y / img.y)
	var s_fit = minf(size.x / bb.size.x, size.y / bb.size.y)
	var s = minf(s_cover, s_fit)
	var win = size / s
	var pos = bb.get_center() - win / 2.0
	for ax in 2:   # keep the window inside the art where it fits; otherwise centre on the sprites
		if win[ax] <= img[ax]: pos[ax] = clampf(pos[ax], 0.0, img[ax] - win[ax])
	return {"kind": kind, "scale": s, "offset": -pos * s, "img": img}

func _draw() -> void:
	if size.x < 2 or size.y < 2: return
	var vt = view_transform()
	var s: float = vt.scale
	var off: Vector2 = vt.offset
	var img: Vector2 = vt.img
	var tex: Texture2D = BG[vt.kind]
	var r = Rect2(off, img * s)
	draw_rect(Rect2(Vector2.ZERO, size), AP.SKY)
	# mirrored fill where the art doesn't reach (only when zoomed out to keep every sprite on screen)
	if r.position.x > 0.0: _draw_mirrored(tex, Vector2(r.position.x, r.position.y), Vector2(-1, 1), r.size)
	if r.end.x < size.x: _draw_mirrored(tex, Vector2(r.end.x + r.size.x, r.position.y), Vector2(-1, 1), r.size)
	if r.position.y > 0.0: _draw_mirrored(tex, Vector2(r.position.x, r.position.y), Vector2(1, -1), r.size)
	if r.end.y < size.y: _draw_mirrored(tex, Vector2(r.position.x, r.end.y + r.size.y), Vector2(1, -1), r.size)
	draw_texture_rect(tex, r, false)
	var lay: Dictionary = LAYOUT[vt.kind]
	var t: Dictionary = profile.tasks if profile else {}
	var dc: Dictionary = profile.decor if profile else {}
	for id in ["lighthouse", "boats", "dock", "cafe", "flowers"]:   # back to front
		var restored = t.has(id)
		var tint: Color = DECOR_TINT[id][clampi(int(dc.get(id, 0)), 0, DECOR_TINT[id].size() - 1)] if restored else Color.WHITE
		if restored and id == reveal_id and _reveal_t < REVEAL_S:
			var k = clampf(_reveal_t / REVEAL_S, 0.0, 1.0)
			k = k * k * (3.0 - 2.0 * k)   # smoothstep
			_draw_sprite(id, lay, false, off, s, Color(1, 1, 1, 1.0 - k))
			_draw_sprite(id, lay, true, off, s, Color(tint, k))
			var rr = _rect_of(id, lay, true)
			var c = off + rr.get_center() * s
			draw_arc(c, (0.35 + 0.5 * k) * maxf(rr.size.x, rr.size.y) * s * 0.6, 0, TAU, 48, Color(AP.STAR_GOLD, 0.6 * (1.0 - k)), 3.0, true)
		else:
			_draw_sprite(id, lay, restored, off, s, tint)

## Draw the art flipped about `at` (scale (-1,1) = horizontal mirror, (1,-1) = vertical).
func _draw_mirrored(tex: Texture2D, at: Vector2, flip: Vector2, sz: Vector2) -> void:
	draw_set_transform(at, 0.0, flip)
	draw_texture_rect(tex, Rect2(Vector2.ZERO, sz), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_sprite(id: String, lay: Dictionary, restored: bool, off: Vector2, s: float, mod: Color) -> void:
	var rr = _rect_of(id, lay, restored)
	draw_texture_rect(_sprite(id, restored), Rect2(off + rr.position * s, rr.size * s), false, mod)
