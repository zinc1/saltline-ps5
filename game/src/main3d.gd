extends Node
## 3D entry point for the native PS5 build.
##
## Needs an engine compiled with disable_3d=no (Node3D + MeshInstance3D +
## Camera3D + GodotPhysics3D).  On the 2D-only engine this prints a clear
## message instead of a grey screen.

var level: Node3D = null
var hud: CanvasLayer = null
var _enemies_root: Node3D = null
var _enemies_spawned := false


func _ready() -> void:
	Boot.note("CAP3D node3d=%s mesh=%s cam=%s phys3d=%s joypads=%d" % [
		ClassDB.class_exists("Node3D"),
		ClassDB.class_exists("MeshInstance3D"),
		ClassDB.class_exists("Camera3D"),
		ClassDB.class_exists("CharacterBody3D"),
		Input.get_connected_joypads().size(),
	])
	if not ClassDB.class_exists("Node3D") or not ClassDB.class_exists("Camera3D"):
		_show_unsupported()
		return
	_build()


func _build() -> void:
	Boot.note("STAGE level3d create")
	level = load("res://src/world/level.gd").new()
	level.name = "Level"
	add_child(level)
	level.build(Game.seed_value)
	Game.level = level

	_enemies_root = Node3D.new()
	_enemies_root.name = "Enemies"
	level.add_child(_enemies_root)

	hud = CanvasLayer.new()
	hud.name = "HUD"
	hud.set_script(load("res://src/ui/hud.gd"))
	add_child(hud)

	_make_rain()
	Boot.note("STAGE spawn_player3d")
	var p = load("res://src/player/player.gd").new()
	p.name = "Breacher"
	p.position = level.player_start
	level.add_child(p)

	Game.state_changed.connect(_on_state)
	Game.player_died.connect(_on_player_died)
	Game.set_state(Game.State.TITLE)
	Boot.note("STAGE boot complete 3d viewport=%s" % str(get_viewport().get_visible_rect().size))

	# Host-side preview hooks (never used on the console).
	var user_args := OS.get_cmdline_user_args()
	if "--autostart" in user_args:
		await get_tree().create_timer(0.4).timeout
		Game.set_state(Game.State.PLAYING)
	if "--shot" in user_args:
		await get_tree().create_timer(2.5).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png("/tmp/saltline_3d.png")
		print("SHOT_SAVED /tmp/saltline_3d.png")
		get_tree().quit()


func _make_rain() -> void:
	# CPU particles keep this working on the GLES3/Compatibility renderer
	# without compute shaders (GPU particles are not guaranteed there).
	var rain := CPUParticles3D.new()
	rain.name = "Rain"
	rain.amount = 1100
	rain.lifetime = 1.5
	rain.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(26, 2, 26)
	rain.direction = Vector3(0.18, -1.0, 0.06)
	rain.spread = 4.0
	rain.initial_velocity_min = 16.0
	rain.initial_velocity_max = 26.0
	rain.gravity = Vector3(0, -14, 0)
	rain.particle_flag_align_y = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.018, 0.62)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.62, 0.72, 0.84, 0.30)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	rain.mesh = quad
	add_child(rain)


func _on_state(state: String) -> void:
	if state == "playing" and not _enemies_spawned:
		_enemies_spawned = true
		level.spawn_enemies(_enemies_root)
		Boot.note("ENEMIES3D spawned count=%d" % _enemies_root.get_child_count())
		Game.message.emit("Cut three uplinks. Reach the boat.", 4.0)


func _on_player_died() -> void:
	Game.message.emit("Breacher down", 3.0)


func _process(_delta: float) -> void:
	if level == null or Game.player == null:
		return
	var rain := get_node_or_null("Rain") as CPUParticles3D
	if rain:
		rain.global_position = Game.player.global_position + Vector3(0, 9, 0)
	if Game.state == Game.State.PLAYING and Game.relay_cut_count >= Game.RELAY_TOTAL:
		var p = Game.player
		if p.global_position.distance_to(level.boat_position) < 5.0:
			Game.set_state(Game.State.COMPLETE)


func _show_unsupported() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.043, 0.051, 0.059)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var label := Label.new()
	label.text = "SALTLINE - 3D runtime unavailable\n\nThis engine was built with disable_3d=yes."
	label.add_theme_font_size_override("font_size", 30)
	label.position = Vector2(160, 420)
	label.custom_minimum_size = Vector2(1600, 200)
	layer.add_child(label)
