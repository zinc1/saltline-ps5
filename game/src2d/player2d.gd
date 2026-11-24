extends CharacterBody2D
## Top-down breacher. Left stick moves, right stick aims, L2 aims down sights
## (analog), R2 fires (analog). Runs on the Canvas2D renderer the PS5 runtime
## actually supports.

const SPEED := 4.6
const SPRINT := 7.4
const CROUCH_SPEED := 2.2
const ACCEL := 42.0
const FRICTION := 16.0
const RADIUS := 0.34

var health := 100.0
var max_health := 100.0
var alive := true
var ads := 0.0
var aim_dir := Vector2.RIGHT
var rifle: Node = null
var camera = null

var _sprinting := false
var _crouching := false
var _step_accum := 0.0
var _prev := {}
var _body: Polygon2D
var _muzzle: Polygon2D


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1

	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = RADIUS
	cs.shape = shape
	add_child(cs)

	_body = Polygon2D.new()
	_body.polygon = PackedVector2Array([
		Vector2(-0.30, -0.26), Vector2(0.34, 0.0), Vector2(-0.30, 0.26),
	])
	_body.color = Color(0.88, 0.89, 0.85)
	add_child(_body)

	_muzzle = Polygon2D.new()
	_muzzle.polygon = PackedVector2Array([Vector2(0.34, -0.05), Vector2(0.62, 0.0), Vector2(0.34, 0.05)])
	_muzzle.color = Color(1.0, 0.72, 0.30)
	add_child(_muzzle)


	rifle = load("res://src2d/rifle2d.gd").new()
	add_child(rifle)
	rifle.setup(self)

	Game.player = self


func _physics_process(delta: float) -> void:
	if not alive:
		return
	if Game.state != Game.State.PLAYING:
		velocity = Vector2.ZERO
		return
	_read_pad(delta)
	_move(delta)
	_body.rotation = aim_dir.angle()
	_muzzle.rotation = aim_dir.angle()


func _read_pad(delta: float) -> void:
	ads = Pad.lt
	rifle.set_aim(ads)
	_update_triggers()

	# aim: right stick first, then arrow keys / mouse-free fallback
	var aim := Vector2(Pad.rx, Pad.ry)
	if aim.length() > 0.30:
		aim_dir = aim.normalized()
	else:
		var ka := Vector2(
			float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT)),
			float(Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_UP))
		)
		if ka.length() > 0.1:
			aim_dir = ka.normalized()

	_sprinting = Pad.btn(JOY_BUTTON_LEFT_SHOULDER) or Input.is_physical_key_pressed(KEY_SHIFT)

	if _once(JOY_BUTTON_B) or Input.is_physical_key_pressed(KEY_C):
		_crouching = not _crouching
	if _once(JOY_BUTTON_Y) or Input.is_physical_key_pressed(KEY_E):
		_try_interact()
	if _once(JOY_BUTTON_X) or Input.is_physical_key_pressed(KEY_R):
		rifle.reload()
	if _once(JOY_BUTTON_RIGHT_SHOULDER) or Input.is_physical_key_pressed(KEY_F):
		_melee()
	if _once(JOY_BUTTON_START) or Input.is_physical_key_pressed(KEY_ESCAPE):
		Game.set_state(Game.State.PAUSED)


func _once(b: int) -> bool:
	var now: bool = Pad.btn(b)
	var was: bool = bool(_prev.get(b, false))
	_prev[b] = now
	return now and not was


func _move(delta: float) -> void:
	var input := Vector2(Pad.lx, Pad.ly)
	var keys := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	)
	if keys.length() > 0.01:
		input = keys.normalized()
	if input.length() > 1.0:
		input = input.normalized()

	var speed := CROUCH_SPEED if _crouching else (SPRINT if _sprinting else SPEED)
	speed *= lerpf(1.0, 0.62, ads)  # aiming slows you down

	var target := input * speed
	velocity = velocity.move_toward(target, ACCEL * delta)
	if input.length() < 0.05:
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
	move_and_slide()

	if velocity.length() > 1.2:
		_step_accum += velocity.length() * delta
		if _step_accum >= 1.4:
			_step_accum = 0.0
			Haptics.play("step")
			Sfx.play("step")


## R2 firms up as the trigger is pulled; L2 gives aim-down-sights a slightly
## heavier ramp.  Adaptive-trigger effects are sticky, so these are cheap:
## Pad only writes when the shape actually changes.
func _update_triggers() -> void:
	var firm := 2 + int(round(ads * 2.0))
	Pad.set_trigger_base(1, 5, 1, 9, firm, mini(firm + 4, 8))
	var brake := 1 + int(round(ads * 2.0))
	Pad.set_trigger_base(0, 5, 1, 8, brake, mini(brake + 2, 8))


func _try_interact() -> void:
	for r in get_tree().get_nodes_in_group("relay"):
		if r.global_position.distance_to(global_position) < 1.9:
			r.cut()
			return


func _melee() -> void:
	Haptics.play("melee")
	Sfx.play("melee")
	var hit := _ray(2.0, 4)
	if hit.is_empty():
		return
	var col: Object = hit.get("collider")
	if col and col.is_in_group("enemy") and col.has_method("damage"):
		col.call("damage", 55.0, hit.get("position", global_position), aim_dir, "body")


func _ray(dist: float, mask: int) -> Dictionary:
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(global_position, global_position + aim_dir * dist)
	q.collision_mask = mask
	q.exclude = [get_rid()]
	return space.intersect_ray(q)


func damage(amount: float, from: Vector2) -> void:
	if not alive:
		return
	health = maxf(0.0, health - amount)
	Game.player_damaged.emit(amount, from)
	Haptics.play("hurt" if amount > 12.0 else "hurt_low")
	Sfx.play("hurt")
	Pad.pulse_trigger(0, 3, 5, 7, 25, 0, 0.16)
	Pad.pulse_trigger(1, 3, 5, 7, 25, 0, 0.16)
	if health <= 0.0:
		alive = false
		Haptics.stop_all()
		Pad.pulse_trigger(0, 3, 3, 8, 40, 0, 0.35)
		Pad.pulse_trigger(1, 3, 3, 8, 40, 0, 0.35)
		Game.set_state(Game.State.DEAD)
		Game.player_died.emit()
