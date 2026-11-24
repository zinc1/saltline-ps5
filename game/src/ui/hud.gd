extends CanvasLayer
## Controller-first HUD and menus. Every screen is navigable with the D-pad,
## Cross and Circle — no mouse required (the PS5 has none).

const INK := Color(0.043, 0.051, 0.059, 0.92)
const BONE := Color(0.91, 0.89, 0.855)
const DIM := Color(0.91, 0.89, 0.855, 0.55)
const SIGNAL := Color(1.0, 0.70, 0.28)
const ALARM := Color(1.0, 0.35, 0.25)

var _crosshair: Control
var _health_bar: ColorRect
var _health_label: Label
var _ammo_label: Label
var _obj_label: Label
var _msg_label: Label
var _msg_left := 0.0
var _overlay: Control
var _overlay_title: Label
var _overlay_body: Label
var _options: Array = []
var _selected := 0
var _overlay_kind := ""


var _hurt_flash: ColorRect
var _prompt: Label


func _ready() -> void:
	layer = 10
	_build_crosshair()
	_build_bars()
	_build_hurt_flash()
	_build_prompt()

	Game.message.connect(_on_message)
	Game.objective_changed.connect(_on_objective)
	Game.state_changed.connect(_on_state)
	_on_objective(0, Game.RELAY_TOTAL)
	_show_overlay("title")


func _build_hurt_flash() -> void:
	_hurt_flash = ColorRect.new()
	_hurt_flash.color = Color(0.75, 0.10, 0.06, 0.0)
	_hurt_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hurt_flash)
	Game.player_damaged.connect(_on_player_damaged)


func _build_prompt() -> void:
	_prompt = _make_label("", 26, SIGNAL)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-300, -230)
	_prompt.custom_minimum_size = Vector2(600, 40)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.visible = false
	add_child(_prompt)


func _update_prompt() -> void:
	if Game.state != Game.State.PLAYING or Game.player == null:
		_prompt.visible = false
		return
	var best := 999.0
	for r in get_tree().get_nodes_in_group("relay"):
		if bool(r.get_meta("cut", false)):
			continue
		var d: float = Game.player.global_position.distance_to(r.global_position)
		best = minf(best, d)
	if best < 3.2:
		_prompt.text = "△  CUT UPLINK"
		_prompt.visible = true
	else:
		_prompt.visible = false


func _on_player_damaged(amount, _from) -> void:
	var a: float = clampf(0.18 + float(amount) * 0.006, 0.18, 0.45)
	_hurt_flash.color.a = a
	var t := create_tween()
	t.tween_property(_hurt_flash, "color:a", 0.0, 0.42)


func _build_crosshair() -> void:
	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.draw.connect(_draw_crosshair)
	add_child(_crosshair)


func _draw_crosshair() -> void:
	var c := _crosshair.size * 0.5
	var spread := 6.0 + lerpf(10.0, 2.0, _ads())
	var col := Color(0.92, 0.90, 0.86, 0.85)
	for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		_crosshair.draw_line(c + dir * spread, c + dir * (spread + 7.0), col, 1.6)
	var dot := Color(1.0, 0.70, 0.28, 0.9)
	_crosshair.draw_circle(c, 1.7, dot)


func _ads() -> float:
	var p = Game.player
	if p == null:
		return 0.0
	var v = p.get("ads")
	return float(v) if v != null else 0.0


func _build_bars() -> void:
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bottom.position = Vector2(64, -140)
	bottom.custom_minimum_size = Vector2(340, 90)
	bottom.add_theme_constant_override("separation", 8)
	add_child(bottom)

	_health_label = _make_label("100", 30, BONE)
	bottom.add_child(_health_label)

	_health_bar = ColorRect.new()
	_health_bar.color = SIGNAL
	_health_bar.custom_minimum_size = Vector2(300, 6)
	bottom.add_child(_health_bar)

	_ammo_label = _make_label("24 / 96", 34, BONE)
	_ammo_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ammo_label.position = Vector2(-260, -120)
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo_label.custom_minimum_size = Vector2(200, 40)
	add_child(_ammo_label)

	_obj_label = _make_label("RELAYS 0/3", 24, SIGNAL)
	_obj_label.position = Vector2(64, 54)
	add_child(_obj_label)

	_msg_label = _make_label("", 26, BONE)
	_msg_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_msg_label.position = Vector2(-300, 150)
	_msg_label.custom_minimum_size = Vector2(600, 40)
	_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_msg_label)


func _make_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


func _process(delta: float) -> void:
	if _msg_left > 0.0:
		_msg_left -= delta
		_msg_label.modulate.a = clampf(_msg_left, 0.0, 1.0)
		if _msg_left <= 0.0:
			_msg_label.text = ""

	var p = Game.player
	if p:
		if "health" in p:
			_health_label.text = str(int(ceil(float(p.health))))
			_health_bar.custom_minimum_size = Vector2(300.0 * clampf(float(p.health) / 100.0, 0.0, 1.0), 6)
			_health_bar.color = SIGNAL if float(p.health) > 35.0 else ALARM
		var rifle = p.rifle
		if rifle:
			_ammo_label.text = "%d / %d" % [rifle.ammo, rifle.reserve]

	_crosshair.queue_redraw()
	_update_prompt()
	_navigate_overlay()


func _navigate_overlay() -> void:
	if _options.is_empty():
		return
	var moved := false
	if Pad.btn(JOY_BUTTON_DPAD_DOWN) or Input.is_physical_key_pressed(KEY_DOWN):
		if _edge("down"):
			_selected = (_selected + 1) % _options.size()
			moved = true
	if Pad.btn(JOY_BUTTON_DPAD_UP) or Input.is_physical_key_pressed(KEY_UP):
		if _edge("up"):
			_selected = (_selected - 1 + _options.size()) % _options.size()
			moved = true
	if moved:
		Haptics.play("ui_move")
		Sfx.play("ui_move")
		_render_options()

	if _edge_btn(JOY_BUTTON_A) or _edge_key(KEY_ENTER):
		Haptics.play("ui")
		Sfx.play("ui")
		var cb: Callable = _options[_selected].get("cb", Callable())
		if cb.is_valid():
			cb.call()
	elif _edge_btn(JOY_BUTTON_B) or _edge_key(KEY_ESCAPE):
		if _overlay_kind == "paused":
			Haptics.play("ui")
			Sfx.play("ui")
			Game.set_state(Game.State.PLAYING)


var _edges := {}


func _edge(key: String) -> bool:
	var now := Pad.btn(JOY_BUTTON_DPAD_DOWN if key == "down" else JOY_BUTTON_DPAD_UP)
	var was: bool = bool(_edges.get(key, false))
	_edges[key] = now
	return now and not was


func _edge_btn(b: int) -> bool:
	var now: bool = Pad.btn(b)
	var k := "btn%d" % b
	var was: bool = bool(_edges.get(k, false))
	_edges[k] = now
	return now and not was


func _edge_key(k: int) -> bool:
	var now := Input.is_physical_key_pressed(k)
	var key := "key%d" % k
	var was: bool = bool(_edges.get(key, false))
	_edges[key] = now
	return now and not was


func _on_message(text: String, seconds: float) -> void:
	_msg_label.text = text
	_msg_left = seconds
	_msg_label.modulate.a = 1.0


func _on_objective(cut: int, total: int) -> void:
	_obj_label.text = "RELAYS %d/%d" % [cut, total]


func _on_state(state: String) -> void:
	match state:
		"playing":
			_set_overlay_visible(false)
		"paused":
			_show_overlay("paused")
		"dead":
			_show_overlay("dead")
		"complete":
			_show_overlay("complete")
		"title":
			_show_overlay("title")


func _set_overlay_visible(v: bool) -> void:
	if _overlay:
		_overlay.visible = v
	if not v:
		_options = []
		_overlay_kind = ""


func _show_overlay(kind: String) -> void:
	_overlay_kind = kind
	if _overlay == null:
		_overlay = Control.new()
		_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		var veil := ColorRect.new()
		veil.color = Color(0.02, 0.025, 0.03, 0.86)
		veil.set_anchors_preset(Control.PRESET_FULL_RECT)
		_overlay.add_child(veil)
		add_child(_overlay)

		for child in _overlay.get_children():
			if child is Label:
				child.queue_free()

	var title_text := ""
	var body_text := ""
	match kind:
		"title":
			title_text = "SALTLINE"
			body_text = "Berth 4 · Port Authority breach\nCut the three uplinks. Reach the boat."
			_options = [
				{"text": "Deploy", "cb": func(): Game.set_state(Game.State.PLAYING)},
				{"text": "Controls", "cb": func(): Game.message.emit("L2 aim · R2 fire · X reload · Triangle cut relay · Options pause", 6.0)},
			]
		"paused":
			title_text = "PAUSED"
			body_text = "Operation on hold"
			_options = [
				{"text": "Resume", "cb": func(): Game.set_state(Game.State.PLAYING)},
				{"text": "Restart mission", "cb": func(): get_tree().reload_current_scene()},
				{"text": "Haptics: %s" % ("ON" if float(Game.settings.get("vibration", 1.0)) > 0.0 else "OFF"),
					"cb": func(): _toggle_haptics()},
				{"text": "Shadows: %s" % ("ON" if bool(Game.settings.get("shadows", false)) else "OFF"),
					"cb": func(): _toggle_shadows()},
				{"text": "Controller test", "cb": func(): _test_haptics()},
			]
		"dead":
			title_text = "SIGNAL LOST"
			body_text = "Breacher down."
			_options = [{"text": "Retry", "cb": func(): get_tree().reload_current_scene()}]
		"complete":
			title_text = "SALTLINE IS DARK"
			body_text = "All three uplinks cut."
			_options = [{"text": "Redeploy", "cb": func(): get_tree().reload_current_scene()}]

	_selected = 0
	_overlay.visible = true
	_render_overlay(title_text, body_text)
	_render_options()


func _render_overlay(title_text: String, body_text: String) -> void:
	_overlay_title = _make_label(title_text, 92, BONE)
	_overlay_title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_overlay_title.position = Vector2(-500, 240)
	_overlay_title.custom_minimum_size = Vector2(1000, 110)
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay.add_child(_overlay_title)

	_overlay_body = _make_label(body_text, 24, DIM)
	_overlay_body.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_overlay_body.position = Vector2(-500, 360)
	_overlay_body.custom_minimum_size = Vector2(1000, 80)
	_overlay_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay.add_child(_overlay_body)


func _toggle_shadows() -> void:
	var on := bool(Game.settings.get("shadows", false))
	Game.settings["shadows"] = not on
	if Game.level and Game.level.has_method("set_shadows"):
		Game.level.set_shadows(not on)
	Game.message.emit("Shadows %s" % ("off" if on else "on"), 2.0)
	_show_overlay("paused")


func _test_haptics() -> void:
	Game.message.emit("Rumble + trigger test", 3.5)
	Pad.rumble(0.95, 0.95, 260)
	Pad.pulse_trigger(0, 5, 1, 9, 1, 8, 2.4)
	Pad.pulse_trigger(1, 5, 1, 9, 1, 8, 2.4)
	await get_tree().create_timer(0.6).timeout
	Pad.rumble(0.35, 0.75, 320)
	await get_tree().create_timer(0.5).timeout
	Pad.rumble(0.85, 0.25, 240)
	await get_tree().create_timer(0.5).timeout
	Pad.rumble(0.2, 0.5, 400)


func _toggle_haptics() -> void:
	var on := float(Game.settings.get("vibration", 1.0)) > 0.0
	Game.settings["vibration"] = 0.0 if on else 1.0
	Pad.clear_triggers()
	Game.message.emit("Haptics %s" % ("off" if on else "on"), 2.0)
	_show_overlay("paused")


func _render_options() -> void:
	for child in _overlay.get_children():
		if child is Label and child != _overlay_title and child != _overlay_body:
			child.queue_free()
	var y := 500
	for i in _options.size():
		var prefix := "▶  " if i == _selected else "    "
		var col := SIGNAL if i == _selected else DIM
		var l := _make_label(prefix + str(_options[i].get("text", "")), 30, col)
		l.set_anchors_preset(Control.PRESET_CENTER_TOP)
		l.position = Vector2(-300, y)
		l.custom_minimum_size = Vector2(600, 44)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_overlay.add_child(l)
		y += 52
