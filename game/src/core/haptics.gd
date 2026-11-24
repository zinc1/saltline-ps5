extends Node
## Named haptic presets with per-tag throttling.
## Autoloaded as `Haptics`; gameplay calls Haptics.play("fire").
##
## A 3D FPS fires a lot of events; spamming scePadSetVibration would both
## flood the pad link and turn the controller into mush, so each tag has a
## minimum gap and the strongest pending envelope wins inside `Pad`.

const PRESETS := {
	"fire":       {"weak": 0.34, "strong": 0.52, "ms": 70,  "gap": 45},
	"fire_ads":   {"weak": 0.22, "strong": 0.40, "ms": 60,  "gap": 45},
	"dry":        {"weak": 0.10, "strong": 0.22, "ms": 45,  "gap": 120},
	"reload":     {"weak": 0.16, "strong": 0.30, "ms": 90,  "gap": 200},
	"reload_end": {"weak": 0.26, "strong": 0.44, "ms": 80,  "gap": 120},
	"hit":        {"weak": 0.30, "strong": 0.46, "ms": 70,  "gap": 40},
	"kill":       {"weak": 0.42, "strong": 0.62, "ms": 130, "gap": 90},
	"hurt":       {"weak": 0.62, "strong": 0.95, "ms": 260, "gap": 160},
	"hurt_low":   {"weak": 0.38, "strong": 0.70, "ms": 180, "gap": 400},
	"step":       {"weak": 0.07, "strong": 0.05, "ms": 40,  "gap": 240},
	"land":       {"weak": 0.26, "strong": 0.52, "ms": 110, "gap": 200},
	"jump":       {"weak": 0.10, "strong": 0.08, "ms": 45,  "gap": 160},
	"melee":      {"weak": 0.45, "strong": 0.75, "ms": 150, "gap": 200},
	"boom":       {"weak": 0.85, "strong": 1.00, "ms": 380, "gap": 220},
	"relay":      {"weak": 0.55, "strong": 0.85, "ms": 260, "gap": 300},
	"ui":         {"weak": 0.14, "strong": 0.06, "ms": 30,  "gap": 60},
	"ui_move":    {"weak": 0.05, "strong": 0.00, "ms": 22,  "gap": 55},
	"heartbeat":  {"weak": 0.20, "strong": 0.34, "ms": 120, "gap": 900},
}

var _last_ms := {}


func play(tag: String) -> void:
	var p: Dictionary = PRESETS.get(tag, {})
	if p.is_empty():
		return
	var now := Time.get_ticks_msec()
	var gap: int = int(p.get("gap", 40))
	var prev: int = int(_last_ms.get(tag, -100000))
	if now - prev < gap:
		return
	_last_ms[tag] = now
	Pad.rumble(float(p["weak"]), float(p["strong"]), int(p["ms"]))


## Explicit strength variant for distance/impact scaled effects.
func play_scaled(tag: String, scale: float) -> void:
	var p: Dictionary = PRESETS.get(tag, {})
	if p.is_empty():
		return
	var now := Time.get_ticks_msec()
	var gap: int = int(p.get("gap", 40))
	var prev: int = int(_last_ms.get(tag, -100000))
	if now - prev < gap:
		return
	_last_ms[tag] = now
	var s := clampf(scale, 0.0, 1.0)
	Pad.rumble(float(p["weak"]) * s, float(p["strong"]) * s, int(p["ms"]))


func stop_all() -> void:
	_last_ms.clear()
	Pad.stop_rumble()
