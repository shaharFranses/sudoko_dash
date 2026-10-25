## Pikeydi studio intro ("Pikeydi" -> PKD, v5b zit-pop stains). Godot 4.3, web-safe:
## no threads, no video codecs. Frames are WebP bytes decoded one at a time into a
## single ImageTexture, so GPU memory stays at one 720x720 texture.
##
## Use as an overlay: add pkd_intro.tscn as a child of your first scene and wait for `finished`.
## Or as a boot wrapper: instance it in a tiny boot scene and set `next_scene`.
extends CanvasLayer

signal finished

## Optional: scene to switch to when the intro ends (boot-wrapper mode).
@export_file("*.tscn") var next_scene: String = ""
## Tap / click / any key skips the intro.
@export var skippable: bool = true
## Free this node after `finished` (ignored when `next_scene` is set, the scene change frees it).
@export var auto_free: bool = true

const FRAMES: Resource = preload("pkd_frames.res")

var _bg: ColorRect
var _rect: TextureRect
var _tex: ImageTexture
var _img := Image.new()
var _t := 0.0
var _shown := -1
var _done := false


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bg = ColorRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.color = Color8(0x1E, 0x1B, 0x3A)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)
	_rect = TextureRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	if FRAMES == null or FRAMES.frames.is_empty() or _img.load_webp_from_buffer(FRAMES.frames[0]) != OK:
		push_warning("pkd_intro: frame data missing, skipping intro")
		_finish.call_deferred()
		return
	# Match the letterbox to the decoded frame background exactly (lossy WebP shifts it by ~1/255).
	_bg.color = _img.get_pixel(2, 2)
	_tex = ImageTexture.create_from_image(_img)
	_rect.texture = _tex
	_shown = 0


func _process(delta: float) -> void:
	if _done:
		return
	# A single long hitch (e.g. the first frame after loading) counts as one frame,
	# so it doesn't skip half the animation; normal low frame rates stay real-time.
	_t += delta if delta < 0.25 else 1.0 / FRAMES.fps
	var i := int(_t * FRAMES.fps)
	if i >= FRAMES.frames.size():
		_finish()
		return
	if i != _shown and _img.load_webp_from_buffer(FRAMES.frames[i]) == OK:
		_tex.update(_img)
		_shown = i


func _input(event: InputEvent) -> void:
	if _done or not skippable:
		return
	var pressed: bool = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventKey and event.pressed and not event.echo)
	if pressed:
		get_viewport().set_input_as_handled()
		_finish()


## Total length in seconds (about 1.93 s).
func get_duration() -> float:
	return FRAMES.frames.size() / FRAMES.fps


func skip() -> void:
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	set_process(false)
	finished.emit()
	if next_scene != "":
		get_tree().change_scene_to_file.call_deferred(next_scene)
	elif auto_free:
		queue_free()
