## Offline ad mock (debug builds only; excluded from the release export).
extends RefCounted

const DEFAULT_MODE = "mock_available"
const MODES = ["mock_available", "mock_unavailable", "mock_error", "mock_timeout"]

func handles(m: String) -> bool:
	return m in MODES

func available(m: String) -> bool:
	return m != "mock_unavailable"

func request(ads: Node, m: String) -> String:
	match m:
		"mock_available":
			await ads.get_tree().create_timer(0.6).timeout
			return "finished"
		"mock_timeout":
			await ads.get_tree().create_timer(ads.timeout_s).timeout
			return "timeout"
	await ads.get_tree().process_frame
	return "error"
