## Pikeydi studio intro ("Pikeydi" -> PKD, v5b zit-pop stains). Godot 4.3, web-safe:
## no threads, no video codecs. Frames are WebP bytes; only the frame due *now* is decoded
## into a single ImageTexture, so GPU memory stays at one 720x720 texture.
##
## v1.1: playback is strictly wall-clock driven (Time.get_ticks_msec), frames are skipped
## when the device is slow, the clock starts on the first frame actually drawn, and a hard
## cap (MAX_SECONDS = 2.5) always ends it: final frame shown, `finished` emitted, node freed.
##
## Use as an overlay: add pkd_intro.tscn as a child of your first scene and wait for `finished`.
## Or as a boot wrapper: instance it in a tiny boot scene and set `next_scene`.
extends CanvasLayer

## Emitted once, on the first frame the intro is actually on screen (the clock starts here).
signal started
## Emitted once when the intro ends (natural end, hard cap, skip or missing data).
signal finished

## Optional: scene to switch to when the intro ends (boot-wrapper mode).
@export_file("*.tscn") var next_scene: String = ""
## Tap / click / any key skips the intro.
@export var skippable: bool = true
## Free this node after `finished` (ignored when `next_scene` is set, the scene change frees it).
@export var auto_free: bool = true

const FRAMES: Resource = preload("pkd_frames.res")
## Hard cap, seconds after the intro first became visible.
const MAX_SECONDS := 2.5
## If the first draw is never reported, start the clock anyway after this long (ms after _ready).
const START_FALLBACK_MS := 1000

var _bg: ColorRect
var _rect: TextureRect
var _tex: ImageTexture
var _img := Image.new()
var _n := 0
var _ready_ms := 0
var _start_ms := -1      # wall clock of the first visible frame; -1 until then
var _shown := -1         # index of the frame currently in the texture
var _done := false


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ready_ms = Time.get_ticks_msec()
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
	_n = FRAMES.frames.size()
	# Match the letterbox to the decoded frame background exactly (lossy WebP shifts it by ~1/255).
	_bg.color = _img.get_pixel(2, 2)
	_tex = ImageTexture.create_from_image(_img)
	_rect.texture = _tex
	_shown = 0
	# Start the clock on the first frame that is actually drawn with the intro in it,
	# not at scene load (a slow first frame must not eat into the animation).
	RenderingServer.frame_post_draw.connect(_on_first_draw, CONNECT_ONE_SHOT)


func _on_first_draw() -> void:
	if _start_ms < 0 and not _done:
		_start_ms = Time.get_ticks_msec()
		started.emit()


## Seconds since the intro became visible (0 before that).
func get_elapsed() -> float:
	return 0.0 if _start_ms < 0 else (Time.get_ticks_msec() - _start_ms) / 1000.0


## Natural length in seconds (58 frames / 30 fps = 1.93 s).
func get_duration() -> float:
	return _n / FRAMES.fps if _n > 0 else 0.0


func _process(_delta: float) -> void:
	if _done:
		return
	var now := Time.get_ticks_msec()
	if _start_ms < 0:
		if now - _ready_ms < START_FALLBACK_MS:
			return
		_start_ms = now   # first draw never reported: start anyway so the cap still applies
		started.emit()
	var t := (now - _start_ms) / 1000.0
	# Pick the frame due now from the wall clock; skip any we are late for.
	var i := mini(int(t * FRAMES.fps), _n - 1)
	_show(i)
	# Natural end, or the hard cap whatever the frame rate. _finish() keeps the node for one
	# more draw, so the final frame set here is what is on screen when it goes.
	if t >= get_duration() or t >= MAX_SECONDS:
		_show(_n - 1)
		_finish()


func _show(i: int) -> void:
	if i == _shown:
		return
	if _img.load_webp_from_buffer(FRAMES.frames[i]) == OK:
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


func skip() -> void:
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	set_process(false)
	if RenderingServer.frame_post_draw.is_connected(_on_first_draw):
		RenderingServer.frame_post_draw.disconnect(_on_first_draw)
	finished.emit()
	if next_scene != "":
		get_tree().change_scene_to_file.call_deferred(next_scene)
	elif auto_free:
		# keep the last frame (final PKD on the cap / natural end) on screen for one draw, then go
		await RenderingServer.frame_post_draw
		queue_free()
