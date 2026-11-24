extends CharacterBody3D
## First-person breacher. Owns the camera, reads `Pad` every frame and drives
## look/move/jump/crouch/sprint, with haptics on every physical beat.

const EYE := 1.68
const CROUCH_EYE := 1.05
const WALK := 4.2
const SPRINT := 6.9
const CROUCH_SPEED := 2.0
const ACCEL := 42.0
const AIR_ACCEL := 9.0
const FRICTION := 14.0
const GRAVITY := 21.0
const JUMP_V := 6.2

var health := 100.0
var max_health := 100.0
var alive := true
var crouching := false
var sprinting := false
var ads := 0.0          # 0..1 analog aim-down-sights
var look_pitch := 0.0
var look_yaw := 0.0

var camera: Camera3D
var rifle
var _col: CollisionShape3D
var _capsule: CapsuleShape3D
var _eye_current := EYE
var _bob := 0.0
var _step_dist := 0.0
var _land_guard := 0.0


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(50)

	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.32
	_capsule.height = 1.8
	_col = CollisionShape3D.new()
	_col.shape = _capsule
	_col.position = Vector3(0, 0.9, 0)
	add_child(_col)

	camera = Camera3D.new()
	camera.position = Vector3(0, EYE, 0)
	camera.fov = float(Game.settings["fov"])
	camera.near = 0.05
	camera.far = 400.0
	add_child(camera)

	var torch := SpotLight3D.new()
	torch.light_color = Color(1.0, 0.94, 0.82)
	torch.light_energy = 7.0
	torch.spot_range = 46.0
	torch.spot_angle = 46.0
	torch.spot_attenuation = 0.8
	torch.shadow_enabled = false
	torch.position = Vector3(0.10, -0.06, 0.0)
	camera.add_child(torch)

	rifle = load("res://src/weapons/rifle.gd").new()
	rifle.name = "Rifle"
	camera.add_child(rifle)
	rifle.setup(self)

	Game.player = self
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var s := float(Game.settings["look_sens"]) * lerpf(1.0, float(Game.settings["ads_sens_scale"]), ads)
		apply_look(event.relative * 0.0022 * s)


func apply_look(delta_xy: Vector2) -> void:
	var inv: bool = bool(Game.settings["invert_y"])
	look_yaw -= delta_xy.x
	look_pitch -= delta_xy.y * (-1.0 if inv else 1.0)
	look_pitch = clampf(look_pitch, deg_to_rad(-86.0), deg_to_rad(86.0))
	rotation.y = look_yaw
	camera.rotation.x = look_pitch


func _physics_process(delta: float) -> void:
	if not alive:
		return
	if Game.state != Game.State.PLAYING:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	_read_pad(delta)
	_move(delta)
	_eye_current = lerpf(_eye_current, CROUCH_EYE if crouching else EYE, delta * 9.0)
	camera.position.y = _eye_current + sin(_bob) * 0.035 * minf(velocity.length() / WALK, 1.4)


func _read_pad(delta: float) -> void:
	# --- look: squared response for fine aim, like the web build's curve ---
	var sens := float(Game.settings["look_sens"]) * lerpf(1.0, float(Game.settings["ads_sens_scale"]), ads)
	var mx := Pad.rx * absf(Pad.rx) * 2.4 * sens
	var my := Pad.ry * absf(Pad.ry) * 1.7 * sens
	if absf(mx) > 0.0001 or absf(my) > 0.0001:
		apply_look(Vector2(mx, my) * delta)

	# --- analog triggers ---
	ads = Pad.lt
	_update_triggers()
	camera.fov = lerpf(float(Game.settings["fov"]), float(Game.settings["ads_fov"]), ads)
	rifle.set_aim(ads)
	Game.settings["_ads"] = ads

	# --- buttons (edge cases handled in rifle/level) ---
	if _pressed_once(JOY_BUTTON_A) or Input.is_physical_key_pressed(KEY_SPACE):
		_jump()
	if _pressed_once(JOY_BUTTON_B) or Input.is_physical_key_pressed(KEY_C):
		crouching = not crouching
	if _pressed_once(JOY_BUTTON_Y) or Input.is_physical_key_pressed(KEY_E):
		try_interact()
	if _pressed_once(JOY_BUTTON_X) or Input.is_physical_key_pressed(KEY_R):
		rifle.reload()
	if _pressed_once(JOY_BUTTON_RIGHT_SHOULDER) or Input.is_physical_key_pressed(KEY_F):
		_melee()
	if _pressed_once(JOY_BUTTON_START) or Input.is_physical_key_pressed(KEY_ESCAPE):
		Game.set_state(Game.State.PAUSED)


var _prev_buttons := {}


func _pressed_once(b: int) -> bool:
	var now: bool = Pad.btn(b)
	var before: bool = bool(_prev_buttons.get(b, false))
	_prev_buttons[b] = now
	return now and not before


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

	sprinting = (Pad.btn(JOY_BUTTON_LEFT_SHOULDER) or Input.is_physical_key_pressed(KEY_SHIFT)) \
		and not crouching and input.y < -0.4
	var speed := CROUCH_SPEED if crouching else (SPRINT if sprinting else WALK)

	var wish := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized() * minf(input.length(), 1.0)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var target := wish * speed
	var rate := ACCEL if is_on_floor() else AIR_ACCEL
	horizontal = horizontal.move_toward(target, rate * delta)
	if is_on_floor() and wish.length() < 0.05:
		horizontal = horizontal.move_toward(Vector3.ZERO, FRICTION * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		if _land_guard > 0.0:
			_land_guard -= delta
	move_and_slide()

	if is_on_floor() and velocity.y <= 0.0 and _land_guard <= 0.0 and _was_air:
		_was_air = false
		Haptics.play("land")
		Sfx.play("land")
		_land_guard = 0.25
	elif not is_on_floor():
		_was_air = true

	# footsteps
	if is_on_floor() and horizontal.length() > 0.6:
		_step_dist += horizontal.length() * delta
		var stride := 1.15 if sprinting else (1.5 if crouching else 1.35)
		if _step_dist >= stride:
			_step_dist = 0.0
			Haptics.play("step")
			Sfx.play("step")
			_bob += PI
	else:
		_bob += delta * 2.0


var _was_air := false


func _jump() -> void:
	if is_on_floor() and not crouching:
		velocity.y = JUMP_V
		_was_air = true
		Haptics.play("jump")
		Sfx.play("jump")


## Adaptive triggers: R2 firms up through its travel, L2 gives ADS a slightly
## heavier ramp. Sticky effects, so only shape changes cost a pad write.
func _update_triggers() -> void:
	var firm := 2 + int(round(ads * 2.0))
	Pad.set_trigger_base(1, 5, 1, 9, firm, mini(firm + 4, 8))
	var brake := 1 + int(round(ads * 2.0))
	Pad.set_trigger_base(0, 5, 1, 8, brake, mini(brake + 2, 8))


func try_interact() -> void:
	var hit := _ray_from_camera(3.6)
	if hit.is_empty():
		return
	var col: Object = hit.get("collider")
	if col and col.has_meta("relay_index"):
		var idx: int = int(col.get_meta("relay_index"))
		if not bool(col.get_meta("cut", false)):
			col.set_meta("cut", true)
			if col.has_method("mark_cut"):
				col.call("mark_cut")
			Game.cut_relay(idx)


func _melee() -> void:
	Haptics.play("melee")
	Sfx.play("melee")
	var hit := _ray_from_camera(2.2)
	if hit.is_empty():
		return
	var col: Object = hit.get("collider")
	if col and col.is_in_group("enemy") and col.has_method("damage"):
		col.call("damage", 55.0, hit.get("position", position), (hit.get("position", position) - position).normalized(), "body")


func _ray_from_camera(dist: float) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from + (-camera.global_transform.basis.z) * dist
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	q.collision_mask = 1 | 4
	return space.intersect_ray(q)


func damage(amount: float, from: Vector3) -> void:
	if not alive:
		return
	health = maxf(0.0, health - amount)
	Game.player_damaged.emit(amount, from)
	Pad.pulse_trigger(0, 3, 5, 7, 25, 0, 0.16)
	Pad.pulse_trigger(1, 3, 5, 7, 25, 0, 0.16)
	Haptics.play("hurt" if amount > 12.0 else "hurt_low")
	if health <= 0.0:
		alive = false
		Haptics.stop_all()
		Game.set_state(Game.State.DEAD)
		Game.player_died.emit()
