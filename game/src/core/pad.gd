extends Node
## DualSense / standard-gamepad layer for the PS5 port.
## Autoloaded as `Pad`.
##
## Everything the game needs about the controller lives here:
##   * radial-deadzoned sticks
##   * ANALOG L2/R2 trigger values (0..1), the reason this port exists
##   * dual-motor rumble with an envelope so effects can overlap
##   * edge-triggered button helpers consumed once per frame

signal connected_changed(connected: bool)

const DEADZONE := 0.16
const TRIGGER_DEADZONE := 0.06

# --- live state -------------------------------------------------------------
var device := -1
var connected := false
var lx := 0.0
var ly := 0.0
var rx := 0.0
var ry := 0.0
var lt := 0.0      # analog L2, 0..1
var rt := 0.0      # analog R2, 0..1

# --- rumble bookkeeping -----------------------------------------------------
var _rumble_end_ms := 0
var _rumble_weak := 0.0
var _rumble_strong := 0.0
var _last_poll_ms := 0
var rumble_calls := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100  # poll before gameplay reads us
	_init_bridge()
	_refresh_device()


func _process(_delta: float) -> void:
	_poll()
	_check_rumble_expiry()
	_tick_bridge()


func _refresh_device() -> void:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		if connected:
			connected = false
			device = -1
			connected_changed.emit(false)
		return
	if not connected or not pads.has(device):
		device = pads[0]
		if not connected:
			connected = true
			connected_changed.emit(true)


func _poll() -> void:
	_refresh_device()
	if not connected:
		lx = 0.0
		ly = 0.0
		rx = 0.0
		ry = 0.0
		lt = 0.0
		rt = 0.0
		return

	var raw_lx := Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
	var raw_ly := Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
	var raw_rx := Input.get_joy_axis(device, JOY_AXIS_RIGHT_X)
	var raw_ry := Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y)

	var left := _radial(raw_lx, raw_ly)
	var right := _radial(raw_rx, raw_ry)
	lx = left.x
	ly = left.y
	rx = right.x
	ry = right.y
	lt = maxf(_norm_trigger(Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT)), _ev_lt)
	rt = maxf(_norm_trigger(Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT)), _ev_rt)


## Radial deadzone that keeps full range at the rim (no square clamping).
func _radial(x: float, y: float) -> Vector2:
	var v := Vector2(x, y)
	var len := v.length()
	if len <= DEADZONE:
		return Vector2.ZERO
	var scaled := minf(1.0, (len - DEADZONE) / (1.0 - DEADZONE))
	return v.normalized() * scaled


## Triggers report 0..1 on evdev-style drivers but -1..1 on some others.
func _norm_trigger(v: float) -> float:
	var t := v
	if t < -0.5:
		t = (t + 1.0) * 0.5
	t = clampf(t, 0.0, 1.0)
	if t < TRIGGER_DEADZONE:
		return 0.0
	return (t - TRIGGER_DEADZONE) / (1.0 - TRIGGER_DEADZONE)


func btn(b: int) -> bool:
	if not connected:
		return false
	return Input.is_joy_button_pressed(device, b) or bool(_ev_buttons.get(b, false))


func any_pressed() -> bool:
	if not connected:
		return false
	return btn(JOY_BUTTON_A) or btn(JOY_BUTTON_B) or btn(JOY_BUTTON_START) \
		or btn(JOY_BUTTON_X) or btn(JOY_BUTTON_Y)


# --- rumble -----------------------------------------------------------------
## weak = small/high-frequency motor, strong = large/low-frequency motor.
func rumble(weak: float, strong: float, ms: int) -> void:
	if not connected or device < 0:
		return
	var gain: float = float(Game.settings.get("vibration", 1.0))
	if gain <= 0.0:
		return
	var w := clampf(weak * gain, 0.0, 1.0)
	var s := clampf(strong * gain, 0.0, 1.0)
	var now := Time.get_ticks_msec()
	var end := now + maxi(ms, 0)
	# Overlapping effects: keep the strongest envelope instead of truncating.
	if end >= _rumble_end_ms or s >= _rumble_strong:
		_vib_l = int(round(w * 255.0))
		_vib_s = int(round(s * 255.0))
		_vib_until = end
		_bridge_force = true
		_rumble_end_ms = maxi(end, _rumble_end_ms)
		_rumble_weak = maxf(w, _rumble_weak if now < _rumble_end_ms else 0.0)
		_rumble_strong = maxf(s, _rumble_strong if now < _rumble_end_ms else 0.0)
		_start(_rumble_weak, _rumble_strong, _rumble_end_ms - now)


func stop_rumble() -> void:
	_rumble_end_ms = 0
	_rumble_weak = 0.0
	_rumble_strong = 0.0
	_vib_l = 0
	_vib_s = 0
	_vib_until = 0
	_bridge_force = true
	if connected and device >= 0:
		Input.stop_joy_vibration(device)


func _start(weak: float, strong: float, ms: int) -> void:
	rumble_calls += 1
	_vib_l = int(round(clampf(weak, 0.0, 1.0) * 255.0))
	_vib_s = int(round(clampf(strong, 0.0, 1.0) * 255.0))
	_bridge_force = true
	if connected and device >= 0:
		Input.start_joy_vibration(device, weak, strong, float(maxi(ms, 16)) / 1000.0)


func _check_rumble_expiry() -> void:
	if _rumble_end_ms > 0 and Time.get_ticks_msec() > _rumble_end_ms:
		_rumble_end_ms = 0
		_rumble_weak = 0.0
		_rumble_strong = 0.0
		if connected and device >= 0:
			Input.stop_joy_vibration(device)

# --- native haptics bridge (padctl payload) ---------------------------------
# A payload process cannot own a DualSense handle; padctl borrows the game
# title's pad handle and applies our requests from inside this process.  We
# talk to it through a tiny state file (no networking in the engine build):
#   seq vibL vibS l2mode l2a l2b l2c l2d r2mode r2a r2b r2c r2d
const BRIDGE_DIR := "user://"
const BRIDGE_STATE := "user://pad_state"
const BRIDGE_TMP := "user://pad_state.tmp"

var bridge_ok := false
var bridge_writes := 0
var _bridge_seq := 0
var _bridge_force := true
var _bridge_last_write := 0
var _vib_l := 0
var _vib_s := 0
var _vib_until := 0
var _trig_base := [[0, 0, 0, 0, 0], [0, 0, 0, 0, 0]]   # [L2, R2]
var _trig_temp := [[0, 0, 0, 0, 0], [0, 0, 0, 0, 0]]
var _trig_until := [0, 0]
var _bridge_logged_fail := false


func _init_bridge() -> void:
	# The PS5 title sandbox cannot create /data; user:// is the writable home
	# (mapped to /data/GodotPS5/userdata/godot_app_userdata_Saltline). The
	# in-engine pad driver resolves the same user:// directory natively.
	bridge_ok = true
	Boot.note("PAD bridge dir=%s ok=%s" % [BRIDGE_DIR, str(bridge_ok)])


func bridge_status() -> String:
	return "bridge=%s writes=%d vib=%d/%d trig=%d/%d" % [
		str(bridge_ok), bridge_writes, _vib_l, _vib_s,
		_trig_base[0][0], _trig_base[1][0],
	]


## Base (resting) adaptive-trigger effect. side: 0 = L2, 1 = R2.
## mode 0 off, 1 feedback(pos,str), 2 weapon(start,end,str),
## 3 vibration(pos,amp,freq), 5 slope(start,end,strStart,strEnd).
func set_trigger_base(side: int, mode: int, a := 0, b := 0, c := 0, d := 0) -> void:
	var want := [mode, a, b, c, d]
	if _trig_base[side] == want:
		return
	_trig_base[side] = want
	_bridge_force = true


## Short one-shot effect that falls back to the base effect after `seconds`.
func pulse_trigger(side: int, mode: int, a := 0, b := 0, c := 0, d := 0, seconds := 0.1) -> void:
	_trig_temp[side] = [mode, a, b, c, d]
	_trig_until[side] = Time.get_ticks_msec() + int(seconds * 1000.0)
	_bridge_force = true


func clear_triggers() -> void:
	for side in 2:
		_trig_base[side] = [0, 0, 0, 0, 0]
		_trig_temp[side] = [0, 0, 0, 0, 0]
		_trig_until[side] = 0
	_bridge_force = true


func _effective_trigger(side: int) -> Array:
	var now := Time.get_ticks_msec()
	if now < int(_trig_until[side]) and int(_trig_temp[side][0]) != 0:
		return _trig_temp[side]
	return _trig_base[side]


func _flush_bridge(force := false) -> void:
	if not bridge_ok:
		return
	var now := Time.get_ticks_msec()
	var l2 := _effective_trigger(0)
	var r2 := _effective_trigger(1)
	_bridge_seq += 1
	var line := "%d %d %d %d %d %d %d %d %d %d %d %d %d\n" % [
		_bridge_seq, _vib_l, _vib_s,
		int(l2[0]), int(l2[1]), int(l2[2]), int(l2[3]), int(l2[4]),
		int(r2[0]), int(r2[1]), int(r2[2]), int(r2[3]), int(r2[4]),
	]
	# Write to a temp file and rename it into place: the engine's pad driver
	# opens the real file read-only on another thread, and truncating it
	# underneath that open can fail with EBUSY on the console filesystem.
	var f := FileAccess.open(BRIDGE_TMP, FileAccess.WRITE)
	if f == null:
		if not _bridge_logged_fail:
			_bridge_logged_fail = true
			Boot.note("PAD bridge write failed (error %d)" % FileAccess.get_open_error())
		return
	f.store_string(line)
	f.close()
	var renamed := DirAccess.rename_absolute(BRIDGE_TMP, BRIDGE_STATE)
	if renamed != OK:
		var g := FileAccess.open(BRIDGE_STATE, FileAccess.WRITE)
		if g == null:
			return
		g.store_string(line)
		g.close()
	bridge_writes += 1
	_bridge_last_write = now


func _tick_bridge() -> void:
	var now := Time.get_ticks_msec()
	var changed := _bridge_force
	# expire one-shot trigger pulses back to the base effect
	for side in 2:
		if int(_trig_until[side]) != 0 and now >= int(_trig_until[side]):
			_trig_until[side] = 0
			changed = true
	# expire rumble envelope
	if _vib_until != 0 and now >= _vib_until:
		_vib_until = 0
		if _vib_l != 0 or _vib_s != 0:
			_vib_l = 0
			_vib_s = 0
			changed = true
	if changed or now - _bridge_last_write >= 250:
		_bridge_force = false
		_flush_bridge(changed)

# --- event-path fallback ----------------------------------------------------
# Some PS5 runtime shims deliver pad input only as an InputEvent stream without
# exposing it through Input.get_joy_axis(). Mirror the events so the game still
# receives analog triggers and buttons either way.

var _ev_lt := 0.0
var _ev_rt := 0.0
var _ev_l := Vector2.ZERO
var _ev_r := Vector2.ZERO
var _ev_buttons := {}
var event_path_seen := false


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		event_path_seen = true
		match event.axis:
			JOY_AXIS_TRIGGER_LEFT:
				_ev_lt = _norm_trigger(event.axis_value)
			JOY_AXIS_TRIGGER_RIGHT:
				_ev_rt = _norm_trigger(event.axis_value)
			JOY_AXIS_LEFT_X:
				_ev_l.x = event.axis_value
			JOY_AXIS_LEFT_Y:
				_ev_l.y = event.axis_value
			JOY_AXIS_RIGHT_X:
				_ev_r.x = event.axis_value
			JOY_AXIS_RIGHT_Y:
				_ev_r.y = event.axis_value
	elif event is InputEventJoypadButton:
		event_path_seen = true
		_ev_buttons[event.button_index] = event.pressed