## ScrollContainer that also scrolls when a drag starts on a button (Harbour list on phones).
## Godot's own touch scrolling only sees drags that start on pass-through children (labels, gaps):
## a Button (mouse_filter STOP) swallows the press. Here the drag is watched in _input, before the GUI:
## a press that starts on a Button is a tap until it moves more than drag_threshold; then it becomes a
## scroll and the button's press is cancelled, so lifting the finger does not press it.
## Presses that start anywhere else are left to the built-in scrolling (no double scroll).
extends ScrollContainer

var drag_enabled: bool = true
var drag_threshold: float = 20.0   # logical units (main sets 10 CSS px)
var _tracking: bool = false
var _dragging: bool = false
var _start: Vector2
var _start_scroll: int = 0
var _button: BaseButton = null
var drags: int = 0                 # completed drag-scrolls (tests / QA)

func _input(e: InputEvent) -> void:
	if not drag_enabled or not is_visible_in_tree(): return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_tracking = false
			_dragging = false
			if not get_global_rect().has_point(e.position): return
			_button = _button_at(e.position)
			if _button == null: return   # labels / gaps: built-in scrolling handles it
			_tracking = true
			_start = e.position
			_start_scroll = scroll_vertical
		elif _tracking:
			_tracking = false
			if _dragging:
				_dragging = false
				drags += 1
				get_viewport().set_input_as_handled()   # the release never reaches the button
	elif e is InputEventMouseMotion and _tracking:
		var dy = e.position.y - _start.y
		if not _dragging and absf(dy) > drag_threshold:
			_dragging = true
			_cancel_press()
		if _dragging:
			scroll_vertical = _start_scroll - int(round(dy))
			get_viewport().set_input_as_handled()

## Resets the button's press state (disabling clears press_attempt) without a visible frame in between.
func _cancel_press() -> void:
	if is_instance_valid(_button):
		var was = _button.disabled
		_button.disabled = true
		_button.disabled = was
	_button = null

func _button_at(p: Vector2) -> BaseButton:
	for b in find_children("*", "BaseButton", true, false):
		if b.is_visible_in_tree() and not b.is_queued_for_deletion() and b.get_global_rect().has_point(p):
			return b
	return null
