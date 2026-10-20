## Debug-hook host. In release this is an inert stub: the QA hooks live in res://debug/qa_hooks.gd,
## which is excluded from the release export and only loaded in debug builds.
extends Node

const HOOKS_PATH = "res://debug/qa_hooks.gd"
var enabled: bool = false
var clock_offset_ms: int = 0
var main = null
var hooks = null

func _ready() -> void:
	if OS.is_debug_build() and ResourceLoader.exists(HOOKS_PATH):
		hooks = load(HOOKS_PATH).new()
		enabled = true
		add_child(hooks)

func now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0) + clock_offset_ms

func publish() -> void:
	if hooks: hooks.publish()
