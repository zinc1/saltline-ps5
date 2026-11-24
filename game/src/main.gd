extends Node
## Entry point for the 2D build 鈥?the shape this PS5 runtime actually supports
## (GodotPS5 GLES3 Canvas2D: Node2D/CanvasItem + 2D physics only).

const PPM := 46.0

var view_layer: CanvasLayer = null
var world: Node2D = null
var hud: CanvasLayer = null
var _enemies_root: Node2D = null
var _enemies_spawned := false


func _ready() -> void:
	var pads := Input.get_connected_joypads()
	Boot.note("CAP2D node2d=%s body2d=%s cam2d=%s rect=%s joypads=%d names=%s" % [
		ClassDB.class_exists("Node2D"),
		ClassDB.class_exists("CharacterBody2D"),
		ClassDB.class_exists("Camera2D"),
		ClassDB.class_exists("ColorRect"),
		pads.size(), str(_names(pads)),
	])

	if not ClassDB.class_exists("Node2D") or not ClassDB.class_exists("CharacterBody2D"):
		_show_unsupported()
		return

	_build()


func _names(pads: Array) -> Array:
	var out := []
	for d in pads:
		out.append("%d:%s" % [d, str(Input.get_joy_name(d))])
	return out


func _build() -> void:
	Boot.note("STAGE world2d create")
	view_layer = CanvasLayer.new()
	view_layer.layer = 0
	add_child(view_layer)
	world = load("res://src2d/world2d.gd").new()
	world.name = "World"
	view_layer.add_child(world)
	world.build(Game.seed_value)
	Game.level = world

	_enemies_root = Node2D.new()
	world.add_child(_enemies_root)

	hud = CanvasLayer.new()
	hud.set_script(load("res://src/ui/hud.gd"))
	add_child(hud)

	Boot.note("STAGE spawn_player begin")
	var p = load("res://src2d/player2d.gd").new()
	p.position = world.player_start
	world.add_child(p)
	Boot.note("STAGE spawn_player done")

	Boot.note("STAGE set_state TITLE")
	Game.set_state(Game.State.TITLE)
	Boot.note("VIEW viewport=%s ppm=%.1f" % [str(get_viewport().get_visible_rect().size), PPM])
	Boot.note("STAGE boot complete")

	Game.state_changed.connect(_on_state)
	Game.player_died.connect(_on_player_died)


func _on_state(state: String) -> void:
	match state:
		"playing":
			if not _enemies_spawned:
				_enemies_spawned = true
				world.spawn_enemies(_enemies_root)
				Boot.note("ENEMIES spawned count=%d" % _enemies_root.get_child_count())
				Game.message.emit("Cut three uplinks. Reach the boat.", 4.0)
		"paused":
			Haptics.stop_all()


func _on_player_died() -> void:
	Game.message.emit("Breacher down", 3.0)


func _process(_delta: float) -> void:
	if Game == null or world == null:
		return
	_update_view()
	if Game.state == Game.State.PLAYING and Game.relay_cut_count >= Game.RELAY_TOTAL:
		if Game.player and Game.player.global_position.distance_to(world.extraction_pos) < 2.6:
			Game.set_state(Game.State.COMPLETE)


func _show_unsupported() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.043, 0.051, 0.059)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var label := Label.new()
	label.text = "SALTLINE 鈥?2D runtime unavailable\n\nThis build needs Node2D / CharacterBody2D."
	label.add_theme_font_size_override("font_size", 34)
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.position = Vector2(-500, -100)
	label.custom_minimum_size = Vector2(1000, 200)
	layer.add_child(label)

func _update_view() -> void:
	if view_layer == null or Game.player == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var off: Vector2 = vp * 0.5 - Game.player.position * PPM
	view_layer.transform = Transform2D(Vector2(PPM, 0.0), Vector2(0.0, PPM), off)