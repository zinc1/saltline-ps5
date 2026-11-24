extends CharacterBody2D
## Walker: patrols the yard, spots the breacher, closes in and shoots.

const SPEED := 1.9
const CHASE := 2.9
const SIGHT := 15.0
const FIRE_RANGE := 11.0
const FIRE_INTERVAL := 1.35
const DAMAGE := 6.0

var health := 90.0
var alive := true
var state := "patrol"

var _target = null
var _fire_cd := 1.0
var _los_cd := 0.0
var _see := false
var _home := Vector2.ZERO
var _dir := 1.0
var _body: Polygon2D


func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 4
	collision_mask = 1
	_home = global_position

	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 0.38
	cs.shape = shape
	add_child(cs)

	_body = Polygon2D.new()
	_body.polygon = PackedVector2Array([
		Vector2(-0.34, -0.34), Vector2(0.38, -0.22), Vector2(0.38, 0.22), Vector2(-0.34, 0.34),
	])
	_body.color = Color(0.72, 0.26, 0.22)
	add_child(_body)
	Boot.note("ENEMY spawned at (%.1f,%.1f)" % [global_position.x, global_position.y])


func _physics_process(delta: float) -> void:
	if not alive:
		return
	if _target == null:
		_target = Game.player

	_los_cd -= delta
	if _los_cd <= 0.0:
		_los_cd = 0.25
		_see = _check_sight()
	if _target and _see:
		state = "alert"

	if state == "patrol":
		_patrol()
	else:
		_chase(delta)
	move_and_slide()
	if _body:
		_body.rotation = velocity.angle() if velocity.length() > 0.1 else _body.rotation


func _patrol() -> void:
	var off := global_position.x - _home.x
	if absf(off) > 4.0:
		_dir = -signf(off)
	velocity = Vector2(_dir * SPEED, 0.0)


func _chase(delta: float) -> void:
	if _target == null:
		return
	var to: Vector2 = _target.global_position - global_position
	var dist := to.length()
	velocity = to.normalized() * CHASE if dist > FIRE_RANGE * 0.7 else Vector2.ZERO

	_fire_cd -= delta
	if _fire_cd <= 0.0 and dist < FIRE_RANGE and _see:
		_fire_cd = FIRE_INTERVAL * randf_range(0.85, 1.25)
		_shoot(to.normalized(), dist)


func _check_sight() -> bool:
	if _target == null:
		return false
	var from := global_position
	var to: Vector2 = _target.global_position
	if from.distance_to(to) > SIGHT:
		return false
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(from, to)
	q.collision_mask = 1
	q.exclude = [get_rid()]
	return space.intersect_ray(q).is_empty()


func _shoot(dir: Vector2, dist: float) -> void:
	var spread := 0.05 + dist * 0.012
	var d := dir.rotated(randf_range(-spread, spread))
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(global_position, global_position + d * (dist + 1.0))
	q.collision_mask = 1 | 2
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var col: Object = hit.get("collider")
	if col and col.is_in_group("player") and col.has_method("damage"):
		col.call("damage", DAMAGE * randf_range(0.8, 1.2), global_position)


func damage(amount: float, _point: Vector2, _dir: Vector2, _part: String) -> bool:
	if not alive:
		return false
	health -= amount
	if _body:
		_body.color = Color(1.0, 0.55, 0.35)
		_flash_back()
	if health <= 0.0:
		alive = false
		collision_layer = 0
		set_physics_process(false)
		_body.modulate = Color(0.35, 0.12, 0.10)
		_body.scale = Vector2(1.3, 1.3)
		return true
	return false


func _flash_back() -> void:
	await get_tree().create_timer(0.12).timeout
	if is_instance_valid(_body):
		_body.color = Color(0.72, 0.26, 0.22)
