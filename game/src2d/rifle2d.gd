extends Node
## 2D rifle: analog R2 pull fires, analog L2 tightens spread. Same tuning as the
## 3D build, hitscan over the 2D physics world.

const RPM := 420.0
const MAG := 24
const RESERVE_MAX := 96
const DAMAGE := 28.0
const RANGE := 26.0
const SPREAD_HIP := 0.11
const SPREAD_ADS := 0.025
const FIRE_THRESHOLD := 0.32
const RELEASE_THRESHOLD := 0.18

var player: CharacterBody2D
var ammo := MAG
var reserve := RESERVE_MAX
var reloading := false
var aim := 0.0
var shots := 0
var hits := 0

var _cooldown := 0.0
var _reload_left := 0.0
var _latched := false


func setup(p: CharacterBody2D) -> void:
	player = p


func set_aim(v: float) -> void:
	aim = clampf(v, 0.0, 1.0)


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
	if reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()
		return
	if Game.state != Game.State.PLAYING or player == null or not player.alive:
		return

	var t := Pad.rt
	if not _latched and t >= FIRE_THRESHOLD:
		_latched = true
	elif _latched and t <= RELEASE_THRESHOLD:
		_latched = false

	if (_latched or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) and _cooldown <= 0.0:
		if ammo <= 0:
			Haptics.play("dry")
			Sfx.play("dry")
			Pad.pulse_trigger(1, 3, 2, 8, 60, 0, 0.15)
			_cooldown = 0.28
			return
		_fire()


func _fire() -> void:
	ammo -= 1
	shots += 1
	_cooldown = 60.0 / RPM
	Haptics.play("fire_ads" if aim > 0.5 else "fire")
	Sfx.play("fire_ads" if aim > 0.5 else "fire")
	Pad.pulse_trigger(1, 2, 2, 7, 7, 0, 0.08)

	var spread := lerpf(SPREAD_HIP, SPREAD_ADS, aim)
	var dir: Vector2 = player.aim_dir.rotated(randf_range(-spread, spread))
	var from: Vector2 = player.global_position
	var to: Vector2 = from + dir * RANGE

	var space: PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(from, to)
	q.collision_mask = 1 | 4
	q.exclude = [player.get_rid()]
	var hit: Dictionary = space.intersect_ray(q)

	var end: Vector2 = to
	if not hit.is_empty():
		end = hit.get("position", to)
		var col: Object = hit.get("collider")
		if col and col.is_in_group("enemy") and col.has_method("damage"):
			hits += 1
			var killed: bool = col.call("damage", DAMAGE * randf_range(0.9, 1.1), end, dir, "body")
			Game.enemy_hit.emit(col, killed, false)
			Haptics.play("kill" if killed else "hit")
			Sfx.play("kill" if killed else "hit")

	_tracer(from, end)
	player.aim_dir = (player.aim_dir + dir.rotated(PI * 0.5) * randf_range(-0.012, 0.012) * (0.6 + Pad.rt)).normalized()


func _tracer(from: Vector2, to: Vector2) -> void:
	var line := Line2D.new()
	line.width = 0.035
	line.default_color = Color(1.0, 0.85, 0.55, 0.85)
	line.add_point(from)
	line.add_point(to)
	player.get_parent().add_child(line)
	var t := get_tree().create_timer(0.05)
	await t.timeout
	if is_instance_valid(line):
		line.queue_free()


func reload() -> void:
	if reloading or ammo >= MAG or reserve <= 0:
		return
	reloading = true
	_reload_left = 1.7
	Haptics.play("reload")
	Sfx.play("reload")
	Pad.pulse_trigger(1, 3, 4, 5, 40, 0, 0.22)
	Pad.pulse_trigger(0, 3, 4, 4, 35, 0, 0.22)


func _finish_reload() -> void:
	reloading = false
	var take: int = mini(MAG - ammo, reserve)
	ammo += take
	reserve -= take
	Haptics.play("reload_end")
	Sfx.play("reload_end")
	Pad.pulse_trigger(1, 1, 7, 6, 0, 0, 0.09)
	Pad.pulse_trigger(0, 1, 7, 5, 0, 0, 0.09)


func accuracy() -> float:
	return 0.0 if shots == 0 else float(hits) / float(shots)
