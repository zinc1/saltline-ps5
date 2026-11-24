extends Node
## Boot telemetry. The console can't be watched from here, so the port writes a
## plain-text report into user:// that is readable over FTP:
##   /data/GodotPS5/userdata/godot_app_userdata_Saltline/saltline_boot.log
## Everything relevant to "does the port work": pack load, scene, joypad
## enumeration, raw trigger axes, frame pacing.

const PATH := "user://saltline_boot.log"

var _frames := 0
var _t := 0.0
var _last_beat := -99.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	note("BOOT engine=%s" % str(Engine.get_version_info().get("string", "?")))
	note("BOOT name=%s main=%s" % [
		str(ProjectSettings.get_setting("application/config/name", "?")),
		str(ProjectSettings.get_setting("application/run/main_scene", "?")),
	])
	note("BOOT user_dir=%s" % OS.get_user_data_dir())
	var pads := Input.get_connected_joypads()
	note("BOOT joypad_count=%d names=%s" % [pads.size(), str(_names(pads))])


func _names(pads: Array) -> Array:
	var out := []
	for d in pads:
		out.append("%d:%s" % [d, str(Input.get_joy_name(d))])
	return out


func note(msg: String) -> void:
	var f := FileAccess.open(PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line("[%d] %s" % [Time.get_ticks_msec(), msg])
	f.close()


func _process(delta: float) -> void:
	if Game == null:
		return
	_frames += 1
	_t += delta
	if _frames == 1:
		var scene := get_tree().current_scene
		note("FRAME1 dt_ms=%.1f scene=%s children=%d" % [
			delta * 1000.0, str(scene.name if scene else "<none>"),
			scene.get_child_count() if scene else -1,
		])
	if _frames == 120:
		_report("T2S")
	if _frames > 120 and _t - _last_beat >= 5.0:
		_report("BEAT")


func _report(tag: String) -> void:
	if Game == null:
		note(tag + " (Game autoload missing)")
		return
	_last_beat = _t
	var pads := Input.get_connected_joypads()
	var lt := -9.0
	var rt := -9.0
	var lx := -9.0
	var ly := -9.0
	if pads.size() > 0:
		var d: int = pads[0]
		lt = Input.get_joy_axis(d, JOY_AXIS_TRIGGER_LEFT)
		rt = Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT)
		lx = Input.get_joy_axis(d, JOY_AXIS_LEFT_X)
		ly = Input.get_joy_axis(d, JOY_AXIS_LEFT_Y)
	var p = Game.player
	var state := Game.state_name(Game.state)
	var hp := -1.0
	var px := 0.0
	var py := 0.0
	if p:
		hp = float(p.health)
		var gp = p.global_position
		px = gp.x
		py = gp.y
	note("%s fps=%.1f frames=%d nodes=%d state=%s relay=%d hp=%.0f pos=(%.1f,%.1f) "
		% [tag, _frames / maxf(_t, 0.001), _frames, get_tree().get_node_count(), state,
			Game.relay_cut_count, hp, px, py]
		+ "pad=%d lt=%.3f rt=%.3f lx=%.3f ly=%.3f rumble_calls=%d"
		% [pads.size(), lt, rt, lx, ly, Pad.rumble_calls]
		+ " " + Pad.bridge_status())
