extends Node3D
## The breacher's rifle: hitscan, 420 rpm, analog-trigger firing, recoil,
## 24-round magazine. R2 is read as a continuous value, so a light pull can be
## treated as a discipline squeeze and a full pull as rapid fire.

const RPM := 420.0
const MAG := 24
const RESERVE_MAX := 96
const DAMAGE := 28.0
const RANGE := 300.0
const RECOIL_KICK := 0.0125
const SPREAD_HIP := 0.026
const SPREAD_ADS := 0.006
const FIRE_THRESHOLD := 0.32
const RELEASE_THRESHOLD := 0.18

var player
var ammo := MAG
var reserve := RESERVE_MAX
var reloading := false
var aim := 0.0
var shots := 0
var hits := 0

var _cooldown := 0.0
var _reload_left := 0.0
var _trigger_latched := false
var _flash: OmniLight3D


func setup(p: CharacterBody3D) -> void:
	player = p
	position = Vector3(0.22, -0.19, -0.36)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.07, 0.09, 0.55)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.11, 0.12, 0.13)
	mat.metallic = 0.6
	mat.roughness = 0.38
	mesh.material_override = mat
	add_child(mesh)

	var barrel := MeshInstance3D.new()
	var bb := CylinderMesh.new()
	bb.top_radius = 0.018
	bb.bottom_radius = 0.022
	bb.height = 0.34
	barrel.mesh = bb
	barrel.rotation_degrees = Vector3(90, 0, 0)
	barrel.position = Vector3(0, 0.015, -0.52)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.08, 0.085, 0.09)
	bm.metallic = 0.9
	bm.roughness = 0.3
	barrel.material_override = bm
	add_child(barrel)

	var sight := MeshInstance3D.new()
	var sb2 := BoxMesh.new()
	sb2.size = Vector3(0.03, 0.035, 0.12)
	sight.mesh = sb2
	sight.position = Vector3(0, 0.075, -0.18)
	sight.material_override = bm
	add_child(sight)

	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.72, 0.4)
	_flash.light_energy = 0.0
	_flash.omni_range = 7.0
	_flash.position = Vector3(0, 0, -0.34)
	add_child(_flash)


func set_aim(v: float) -> void:
	aim = clampf(v, 0.0, 1.0)
	position = Vector3(0.22 - 0.10 * aim, -0.19 + 0.045 * aim, -0.36 + 0.05 * aim)
	rotation = Vector3(0.0, 0.0, 0.0)


func _process(delta: float) -> void:
	if _flash.light_energy > 0.0:
		_flash.light_energy = maxf(0.0, _flash.light_energy - delta * 22.0)
	if _cooldown > 0.0:
		_cooldown -= delta

	if reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()
		return

	if Game.state != Game.State.PLAYING or player == null or not player.alive:
		return

	# analog trigger with hysteresis so a resting finger cannot auto-fire
	var t := Pad.rt
	if not _trigger_latched and t >= FIRE_THRESHOLD:
		_trigger_latched = true
	elif _trigger_latched and t <= RELEASE_THRESHOLD:
		_trigger_latched = false

	var wants := _trigger_latched or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if wants and _cooldown <= 0.0:
		if ammo <= 0:
			Haptics.play("dry")
			Sfx.play("dry")
			Pad.pulse_trigger(1, 3, 2, 8, 60, 0, 0.15)
			_cooldown = 0.28
			return
		_fire()


func _tracer(from: Vector3, to: Vector3) -> void:
	if to.distance_to(from) < 0.2:
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(from)
	im.surface_add_vertex(to)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.86, 0.55, 0.85)
	mi.material_override = m
	player.get_parent().add_child(mi)
	var tween := create_tween()
	tween.tween_property(m, "albedo_color:a", 0.0, 0.07)
	tween.tween_callback(mi.queue_free)


func _fire() -> void:
	ammo -= 1
	shots += 1
	_cooldown = 60.0 / RPM
	_flash.light_energy = 2.4
	Haptics.play("fire_ads" if aim > 0.5 else "fire")
	Sfx.play("fire_ads" if aim > 0.5 else "fire")
	Pad.pulse_trigger(1, 2, 2, 7, 7, 0, 0.08)

	var spread := lerpf(SPREAD_HIP, SPREAD_ADS, aim)
	var dir: Vector3 = -player.camera.global_transform.basis.z
	dir = (dir + player.camera.global_transform.basis.x * randf_range(-spread, spread)
		+ player.camera.global_transform.basis.y * randf_range(-spread, spread)).normalized()

	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var from: Vector3 = player.camera.global_position
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, from + dir * RANGE)
	q.exclude = [player.get_rid()]
	q.collision_mask = 1 | 4
	var hit: Dictionary = space.intersect_ray(q)
	var hit_point: Vector3 = hit.get("position", from + dir * RANGE)
	_tracer(player.camera.global_position, hit_point)

	if not hit.is_empty():
		var col: Object = hit.get("collider")
		if col and col.is_in_group("enemy") and col.has_method("damage"):
			hits += 1
			var killed: bool = col.call("damage", DAMAGE, hit["position"], dir, "body")
			Game.enemy_hit.emit(col, killed, false)
			Haptics.play("kill" if killed else "hit")

	# recoil: push the view up a touch, scaled by how hard the trigger is pulled
	player.apply_look(Vector2(randf_range(-0.0016, 0.0016), -RECOIL_KICK * lerpf(1.0, 0.55, aim) * (0.6 + Pad.rt)))


func reload() -> void:
	if reloading or ammo >= MAG or reserve <= 0:
		return
	reloading = true
	_reload_left = 1.85
	Haptics.play("reload")
	Sfx.play("reload")
	Pad.pulse_trigger(1, 3, 4, 5, 40, 0, 0.22)
	Pad.pulse_trigger(0, 3, 4, 4, 35, 0, 0.22)


func _finish_reload() -> void:
	reloading = false
	var need := MAG - ammo
	var take: int = mini(need, reserve)
	ammo += take
	reserve -= take
	Haptics.play("reload_end")
	Sfx.play("reload_end")
	Pad.pulse_trigger(1, 1, 7, 6, 0, 0, 0.09)
	Pad.pulse_trigger(0, 1, 7, 5, 0, 0, 0.09)


func accuracy() -> float:
	if shots == 0:
		return 0.0
	return float(hits) / float(shots)
