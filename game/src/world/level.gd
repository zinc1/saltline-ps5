extends Node3D
## Saltline Terminal, Berth 4 鈥?procedural harbour blockout.
## Everything here is generated from the run seed, matching the web build's
## approach (no imported assets, no textures).

const INK := Color(0.043, 0.051, 0.059)
const BONE := Color(0.91, 0.89, 0.855)
const RUST := Color(0.82, 0.38, 0.16)
const SIGNAL := Color(1.0, 0.70, 0.28)
const STEEL := Color(0.55, 0.60, 0.64)

var relays: Array[Node3D] = []
var enemy_spawns: Array[Vector3] = []
var player_start := Vector3(0, 0.2, 24)
var boat_position := Vector3(0, 0, -34)
var moon_light: DirectionalLight3D = null

var _rng := RandomNumberGenerator.new()
var _mat_cache := {}
var _batch := {}          # color -> Array[Transform3D] for containers
var _window_spots: Array[Vector3] = []


func build(seed_value: int) -> void:
	Boot.note("LEVEL build seed=%d" % seed_value)
	_rng.seed = seed_value
	_environment()
	_ground()
	_containers()
	_cranes()
	_buildings()
	_relays()
	_boat()
	_spawn_points()
	_flush_batches()
	Boot.note("LEVEL build done relays=%d" % relays.size())


func _environment() -> void:
	var env := Environment.new()
	# Rainy night: near-black blue sky, dense harbour fog, cold moon key with
	# warm sodium dock lamps.  Matches the web build's palette (ink / bone /
	# signal amber) instead of a sunny daylight blockout.
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.012, 0.020, 0.034)
	sm.sky_horizon_color = Color(0.075, 0.095, 0.130)
	sm.sky_curve = 0.12
	sm.ground_bottom_color = Color(0.010, 0.014, 0.020)
	sm.ground_horizon_color = Color(0.045, 0.060, 0.080)
	sm.sun_angle_max = 5.0
	sm.sun_curve = 0.12
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.14, 0.19, 0.27)
	env.ambient_light_energy = 0.72
	env.fog_enabled = true
	env.fog_light_color = Color(0.115, 0.145, 0.185)
	env.fog_density = 0.026
	env.fog_sky_affect = 0.30
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.15
	env.glow_enabled = false
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.05

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.52, 0.64, 0.88)
	moon.light_energy = 0.72
	moon.rotation_degrees = Vector3(-38, 124, 0)
	moon.shadow_enabled = bool(Game.settings.get("shadows", false))
	moon_light = moon
	moon.directional_shadow_max_distance = 100.0
	add_child(moon)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.38, 0.52, 0.72)
	fill.light_energy = 0.22
	fill.rotation_degrees = Vector3(-58, -42, 0)
	fill.shadow_enabled = false
	add_child(fill)
	_dock_lights()


func _dock_lights() -> void:
	# Sodium lamps along the quay: amber pools in the rain, plus tiny emissive
	# heads so the sources read against the sky.
	for i in 4:
		var x := -28.0 + i * 18.0
		var z := -27.0
		var pole := _box(Vector3(0.18, 7.0, 0.18), Vector3(x, 3.5, z),
			Color(0.16, 0.17, 0.18), false, 0.5)
		var head := MeshInstance3D.new()
		var hb := BoxMesh.new()
		hb.size = Vector3(0.7, 0.22, 0.35)
		head.mesh = hb
		var hm := StandardMaterial3D.new()
		hm.albedo_color = SIGNAL
		hm.emission_enabled = true
		hm.emission = SIGNAL
		hm.emission_energy_multiplier = 5.0
		head.material_override = hm
		head.position = Vector3(x, 7.0, z)
		add_child(head)
		var lamp := OmniLight3D.new()
		lamp.light_color = SIGNAL
		lamp.light_energy = 2.6
		lamp.omni_range = 16.0
		lamp.omni_attenuation = 1.2
		lamp.position = Vector3(x, 6.8, z)
		add_child(lamp)


func set_shadows(enabled: bool) -> void:
	if moon_light:
		moon_light.shadow_enabled = enabled


func _material(color: Color, metallic := 0.25, roughness := 0.82) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f" % [color.to_html(), metallic, roughness]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	_mat_cache[key] = m
	return m


func _box(size: Vector3, pos: Vector3, color: Color, solid := true, metallic := 0.25) -> Node3D:
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		body.position = pos
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		mi.mesh = mesh
		mi.material_override = _material(color, metallic)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		body.add_child(mi)
		add_child(body)
		return body
	else:
		var mi2 := MeshInstance3D.new()
		var mesh2 := BoxMesh.new()
		mesh2.size = size
		mi2.mesh = mesh2
		mi2.material_override = _material(color, metallic)
		mi2.position = pos
		add_child(mi2)
		return mi2


func _batch_box(size: Vector3, pos: Vector3, color: Color) -> void:
	if not _batch.has(color):
		_batch[color] = []
	_batch[color].append(Transform3D(Basis().scaled(size), pos))


func _flush_batches() -> void:
	for color in _batch.keys():
		var transforms: Array = _batch[color]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var unit := BoxMesh.new()
		mm.mesh = unit
		mm.instance_count = transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _material(color, 0.35, 0.8)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)
	# lit windows as one draw call
	if not _window_spots.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var quad := QuadMesh.new()
		quad.size = Vector2(0.85, 0.55)
		mm.mesh = quad
		mm.instance_count = _window_spots.size()
		for i in _window_spots.size():
			mm.set_instance_transform(i, Transform3D(Basis(), _window_spots[i]))
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.78, 0.45) * 0.85
		m.emission_enabled = true
		m.emission = Color(1.0, 0.78, 0.45)
		m.emission_energy_multiplier = 1.4
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = m
		add_child(mmi)


func _ground() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(120, 1, 120)
	cs.shape = shape
	cs.position = Vector3(0, -0.5, 0)
	ground.add_child(cs)

	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	mi.mesh = plane
	mi.material_override = _material(Color(0.055, 0.062, 0.070), 0.65, 0.16)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.add_child(mi)
	add_child(ground)

	# wet sea beyond the quay
	var sea := MeshInstance3D.new()
	var seaplane := PlaneMesh.new()
	seaplane.size = Vector2(400, 400)
	sea.mesh = seaplane
	var sea_mat := StandardMaterial3D.new()
	sea_mat.albedo_color = Color(0.025, 0.05, 0.07)
	sea_mat.metallic = 1.0
	sea_mat.roughness = 0.06
	sea.material_override = sea_mat
	sea.position = Vector3(0, -1.6, -90)
	add_child(sea)

	# quay edge
	_box(Vector3(120, 3.2, 1.2), Vector3(0, -0.2, -30.6), Color(0.14, 0.15, 0.16), true, 0.1)


func _containers() -> void:
	var palette := [
		Color(0.52, 0.16, 0.10), Color(0.13, 0.26, 0.34),
		Color(0.30, 0.31, 0.20), Color(0.20, 0.22, 0.24),
		Color(0.45, 0.28, 0.12), Color(0.16, 0.30, 0.28),
	]
	var rows := 7
	var cols := 9
	for r in rows:
		for c in cols:
			if _rng.randf() < 0.22:
				continue
			var long := _rng.randf() < 0.5
			var size := Vector3(2.44, 2.59, 6.06 if not long else 12.19)
			var x := -24.0 + c * 6.0 + _rng.randf_range(-0.35, 0.35)
			var z := -22.0 + r * 6.4 + _rng.randf_range(-0.3, 0.3)
			# keep the central corridor to the relays walkable
			if absf(x) < 3.2:
				continue
			var stacked := _rng.randf() < 0.28
			var color: Color = palette[_rng.randi() % palette.size()]
			_container(size, Vector3(x, size.y * 0.5, z), color)
			if stacked:
				_container(size, Vector3(x, size.y * 1.5, z), palette[_rng.randi() % palette.size()])


func _container(size: Vector3, pos: Vector3, color: Color) -> void:
	# collision stays a StaticBody3D; the visual is batched by colour
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.position = pos
	add_child(body)
	_batch_box(size, pos, color)


func _cranes() -> void:
	# silhouette gantry cranes along the far quay
	for i in 3:
		var x := -28.0 + i * 28.0
		var z := -40.0
		_box(Vector3(1.4, 26, 1.4), Vector3(x - 5, 13, z), Color(0.32, 0.34, 0.36), false, 0.6)
		_box(Vector3(1.4, 26, 1.4), Vector3(x + 5, 13, z), Color(0.32, 0.34, 0.36), false, 0.6)
		_box(Vector3(20, 1.2, 1.6), Vector3(x, 26, z), Color(0.35, 0.30, 0.22), false, 0.6)
		_box(Vector3(0.8, 2.2, 2.0), Vector3(x, 24.6, z + 1.4), RUST, false, 0.5)


func _buildings() -> void:
	for i in 6:
		var x := -34.0 + i * 13.0
		var h := _rng.randf_range(9.0, 22.0)
		_box(Vector3(10, h, 10), Vector3(x, h * 0.5, -52), Color(0.09, 0.10, 0.12), false, 0.2)
		# scattered lit windows: cheap emissive quads on the yard-facing wall
		for row in int(h / 3.0):
			for col in 3:
				if _rng.randf() < 0.55:
					continue
				var wx := x - 3.0 + col * 3.0 + _rng.randf_range(-0.4, 0.4)
				var wy := 2.0 + row * 3.0
				_window_spots.append(Vector3(wx, wy, -46.7))


func _window(pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.85, 0.55)
	mi.mesh = quad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color * 0.85
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 1.4
	mi.material_override = m
	mi.position = pos
	add_child(mi)


func _relays() -> void:
	var spots := [
		Vector3(-17.0, 0, -8.0),
		Vector3(16.0, 0, -14.0),
		Vector3(2.0, 0, -25.0),
	]
	for i in spots.size():
		var relay := StaticBody3D.new()
		relay.collision_layer = 1
		relay.collision_mask = 0
		relay.position = spots[i]
		relay.set_meta("relay_index", i)
		relay.set_meta("cut", false)
		relay.add_to_group("relay")

		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.5, 4.2, 1.5)
		cs.shape = shape
		cs.position = Vector3(0, 2.1, 0)
		relay.add_child(cs)

		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.85, 4.0, 0.85)
		mi.mesh = mesh
		mi.material_override = _material(Color(0.22, 0.24, 0.26), 0.7, 0.4)
		mi.position = Vector3(0, 2.0, 0)
		relay.add_child(mi)

		# signal lamp: bright amber while live, dark red when cut
		var lamp := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.28
		sphere.height = 0.56
		lamp.mesh = sphere
		var lm := StandardMaterial3D.new()
		lm.albedo_color = SIGNAL
		lm.emission_enabled = true
		lm.emission = SIGNAL
		lm.emission_energy_multiplier = 4.0
		lamp.material_override = lm
		lamp.position = Vector3(0, 4.25, 0)
		relay.add_child(lamp)

		var glow := OmniLight3D.new()
		glow.light_color = SIGNAL
		glow.light_energy = 2.2
		glow.omni_range = 9.0
		glow.position = Vector3(0, 4.25, 0)
		relay.add_child(glow)

		relay.set_script(load("res://src/world/relay.gd"))
		relay.set("lamp", lamp)
		relay.set("glow", glow)
		add_child(relay)
		relays.append(relay)


func _boat() -> void:
	var hull := _box(Vector3(7, 2.6, 16), Vector3(0, -0.2, -40), Color(0.10, 0.12, 0.13), false, 0.4)
	hull.rotation_degrees.y = 8.0
	_box(Vector3(4.4, 2.2, 5.0), Vector3(0.6, 1.9, -43), Color(0.16, 0.17, 0.18), false, 0.3)
	boat_position = Vector3(0, 0, -38)
	var lamp := SpotLight3D.new()
	lamp.light_color = Color(1.0, 0.82, 0.55)
	lamp.light_energy = 6.0
	lamp.spot_range = 38.0
	lamp.spot_angle = 42.0
	lamp.position = Vector3(0.6, 6.5, -38)
	lamp.rotation_degrees = Vector3(-62, 0, 0)
	add_child(lamp)


func _spawn_points() -> void:
	enemy_spawns = [
		Vector3(7, 0.2, 8),
		Vector3(-8, 0.2, 12),
		Vector3(-22, 0.2, -10),
		Vector3(20, 0.2, -6),
		Vector3(-8, 0.2, -20),
		Vector3(12, 0.2, -24),
		Vector3(-14, 0.2, -28),
		Vector3(24, 0.2, -18),
	]


func spawn_enemies(parent: Node3D) -> void:
	var script := load("res://src/enemies/walker.gd")
	for pos in enemy_spawns:
		var e := CharacterBody3D.new()
		e.set_script(script)
		e.position = pos
		parent.add_child(e)
