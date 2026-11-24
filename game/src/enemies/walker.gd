extends CharacterBody3D
## Walker drone: patrols, spots the breacher, closes distance, fires bursts.
## Deliberately simple state machine — this is the first playable pass.

const SPEED := 2.6
const CHASE_SPEED := 3.4
const SIGHT := 26.0
const FIRE_RANGE := 16.0
const FIRE_INTERVAL := 1.35
const DAMAGE := 6.0

var health := 90.0
var alive := true
var state := "patrol"

var _target
var _fire_cd := 1.0
var _los_cd := 0.0
var _can_see := false
var _home: Vector3
var _patrol_dir := 1.0
var _mesh: MeshInstance3D
var _col: CollisionShape3D


func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 4
	collision_mask = 1
	_home = global_position

	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.75
	_col = CollisionShape3D.new()
	_col.shape = cap
	_col.position = Vector3(0, 0.88, 0)
	add_child(_col)

	_mesh = MeshInstance3D.new()
	var body := CapsuleMesh.new()
	body.radius = 0.36
	body.height = 1.7
	_mesh.mesh = body
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.20, 0.22)
	mat.metallic = 0.6
	mat.roughness = 0.55
	_mesh.material_override = mat
	_mesh.position = Vector3(0, 0.88, 0)
	add_child(_mesh)

	# glowing visor so the silhouette reads at night
	var visor := MeshInstance3D.new()
	var vb := BoxMesh.new()
	vb.size = Vector3(0.3, 0.06, 0.05)
	visor.mesh = vb
	var vm := StandardMaterial3D.new()
	vm.albedo_color = Color(1.0, 0.31, 0.25)
	vm.emission_enabled = true
	vm.emission = Color(1.0, 0.31, 0.25)
	vm.emission_energy_multiplier = 3.0
	visor.material_override = vm
	visor.position = Vector3(0, 1.45, -0.31)
	add_child(visor)

	# gun arm + shoulder block: reads as a hostile silhouette at night
	var gun := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(0.10, 0.10, 0.72)
	gun.mesh = gb
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.10, 0.11, 0.12)
	gm.metallic = 0.7
	gm.roughness = 0.4
	gun.material_override = gm
	gun.position = Vector3(0.28, 1.05, -0.42)
	add_child(gun)

	var shoulders := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.62, 0.16, 0.30)
	shoulders.mesh = sb
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.22, 0.24, 0.27)
	sm.metallic = 0.5
	shoulders.material_override = sm
	shoulders.position = Vector3(0, 1.52, 0)
	add_child(shoulders)


func _physics_process(delta: float) -> void:
	if not alive:
		return
	if _target == null:
		_target = Game.player

	_los_cd -= delta
	if _los_cd <= 0.0:
		_los_cd = 0.22
		_can_see = _check_sight()

	if _target and _can_see:
		state = "alert"

	match state:
		"patrol":
			_patrol(delta)
		"alert":
			_chase(delta)

	if not is_on_floor():
		velocity.y -= 21.0 * delta
	move_and_slide()


func _patrol(delta: float) -> void:
	var offset := global_position - _home
	if absf(offset.x) > 6.0:
		_patrol_dir = -signf(offset.x)
	velocity.x = _patrol_dir * SPEED
	velocity.z = 0.0
	_face(Vector3(_patrol_dir, 0, 0), delta)


func _chase(delta: float) -> void:
	if _target == null:
		return
	var to: Vector3 = _target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	_face(to, delta)
	if dist > FIRE_RANGE * 0.72:
		velocity.x = (to.normalized() * CHASE_SPEED).x
		velocity.z = (to.normalized() * CHASE_SPEED).z
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	_fire_cd -= delta
	if _fire_cd <= 0.0 and dist < FIRE_RANGE and _can_see:
		_fire_cd = FIRE_INTERVAL * randf_range(0.85, 1.25)
		_shoot(dist)


func _face(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01:
		return
	var want := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, want, delta * 6.0)


func _check_sight() -> bool:
	if _target == null:
		return false
	var from := global_position + Vector3(0, 1.45, 0)
	var to: Vector3 = _target.global_position + Vector3(0, 1.1, 0)
	if from.distance_to(to) > SIGHT:
		return false
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	return hit.is_empty()


func _shoot(dist: float) -> void:
	if _target == null:
		return
	var from := global_position + Vector3(0, 1.4, 0)
	var aim: Vector3 = _target.global_position + Vector3(0, 1.0, 0)
	var dir: Vector3 = (aim - from).normalized()
	# spread grows with distance, so far shots miss more often
	var spread := 0.012 + dist * 0.0016
	dir = (dir + Vector3(randf_range(-spread, spread), randf_range(-spread, spread), randf_range(-spread, spread))).normalized()

	Game.explosion.emit(from, 0.01)  # cheap "gunfire" beacon for haptics/UI hooks
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * dist + dir * 2.0)
	q.collision_mask = 1 | 2
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var col: Object = hit.get("collider")
	if col and col.is_in_group("player") and col.has_method("damage"):
		col.call("damage", DAMAGE * randf_range(0.8, 1.2), from)


func damage(amount: float, _point: Vector3, _dir: Vector3, _part: String) -> bool:
	if not alive:
		return false
	health -= amount
	# flash the chassis on hit
	if _mesh:
		var mat := _mesh.material_override as StandardMaterial3D
		if mat:
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.45, 0.25)
			mat.emission_energy_multiplier = 2.0
			var tween := create_tween()
			tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.14)
	if health <= 0.0:
		alive = false
		collision_layer = 0
		set_physics_process(false)
		var t := create_tween()
		t.tween_property(self, "scale", Vector3(1.1, 0.05, 1.1), 0.22)
		t.tween_callback(queue_free)
		return true
	return false
