## Master-mute arbitration (pure logic). Muted while ANY reason is active: "ad", "hidden", "blur", "user", "intro".
extends RefCounted

var reasons: Dictionary = {}

func set_reason(reason: String, active: bool) -> bool:
	if active: reasons[reason] = true
	else: reasons.erase(reason)
	return muted()

func muted() -> bool:
	return not reasons.is_empty()
