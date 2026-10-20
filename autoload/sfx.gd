## Audio plumbing + tiny generated placeholder SFX (no audio files). Autoload "Sfx".
## Master bus is muted while an ad plays (Ads hooks), while the tab is hidden (visibilitychange),
## or when the user mutes. Web AudioContext is resumed on the first tap/key (glue in web/head_include.html).
extends Node

const MuteState = preload("res://game/mute_state.gd")
const RATE = 22050
const SOUNDS = {
	"tap": [[880.0, 0.03]],
	"place": [[660.0, 0.05], [990.0, 0.06]],
	"mistake": [[220.0, 0.12], [180.0, 0.12]],
	"complete": [[523.25, 0.08], [659.25, 0.08], [783.99, 0.08], [1046.5, 0.16]],
}

var state = MuteState.new()
var streams: Dictionary = {}
var played: Array = []   # last sounds (for tests)
var _players: Array = []
var _poll: float = 0.0

func _ready() -> void:
	for k in SOUNDS: streams[k] = _make(SOUNDS[k])
	for i in 4:
		var p = AudioStreamPlayer.new()
		p.volume_db = -10.0
		add_child(p)
		_players.append(p)
	Ads.ad_started.connect(func(): set_reason("ad", true))
	Ads.ad_finished.connect(func(): set_reason("ad", false))

static func _make(notes: Array) -> AudioStreamWAV:
	var data = PackedByteArray()
	for n in notes:
		var f: float = n[0]
		var count = int(RATE * float(n[1]))
		for i in count:
			var env = minf(1.0, minf(i / 200.0, (count - i) / 400.0))
			var v = int(sin(TAU * f * i / RATE) * 9000.0 * env)
			data.append(v & 0xFF)
			data.append((v >> 8) & 0xFF)
	var s = AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s

func set_reason(reason: String, active: bool) -> void:
	var m = state.set_reason(reason, active)
	AudioServer.set_bus_mute(0, m)

func is_muted() -> bool:
	return AudioServer.is_bus_mute(0)

func play(name: String) -> void:
	played.append(name)
	if played.size() > 20: played.pop_front()
	if state.muted() or not streams.has(name): return
	for p in _players:
		if not p.playing:
			p.stream = streams[name]
			p.play()
			return

func _process(delta: float) -> void:
	if not OS.has_feature("web"): return
	_poll += delta
	if _poll < 0.25: return
	_poll = 0.0
	set_reason("hidden", str(JavaScriptBridge.eval("document.hidden ? 'y' : 'n'")) == "y")

func _notification(what: int) -> void:
	# desktop / mobile fallback
	if what == NOTIFICATION_APPLICATION_PAUSED: set_reason("hidden", true)
	elif what == NOTIFICATION_APPLICATION_RESUMED: set_reason("hidden", false)
