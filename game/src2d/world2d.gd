extends Node2D
## Berth 4 in top-down. Seeded container yard, three uplink relays, an
## extraction point at the boat, and rain drawn straight onto the canvas.

const YARD := Vector2(44, 34)
const INK := Color(0.055, 0.062, 0.070)
const SLAB := Color(0.115, 0.125, 0.135)
const RUST := Color(0.52, 0.24, 0.12)
const STEEL := Color(0.30, 0.33, 0.36)
const SIGNAL := Color(1.0, 0.70, 0.28)
const SEA := Color(0.035, 0.065, 0.085)

var player_start := Vector2(0, 12)
var extraction_pos := Vector2(0, -20)
var relays: Array = []
var enemy_spawns: Array = []

var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _rain: Array = []


func build(seed_value: int) -> void:
	_rng.seed = seed_value
	_make_rain()
	_ground()
	_containers()
	_relays()
	_extraction()
	_spawn_points()
	Boot.note("WORLD2D built relays=%d containers_spawns=%d" % [relays.size(), enemy_spawns.size()])


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _make_rain() -> void:
	_rain.clear()
	for i in 170:
		_rain.append(Vector3(
			_rng.randf_range(-YARD.x * 0.6, YARD.x * 0.6),
			_rng.randf_range(-YARD.y * 0.6, YARD.y * 0.6),
			_rng.randf_range(14.0, 26.0)
		))


func _draw() -> void:
	# sea band at the north edge, quay slab elsewhere
	draw_rect(Rect2(Vector2(-YARD.x, -YARD.y - 14), Vector2(YARD.x * 2, 14)), SEA)
	draw_rect(Rect2(Vector2(-YARD.x, -YARD.y), YARD * 2.0), SLAB)
	draw_line(Vector2(-YARD.x, -YARD.y), Vector2(YARD.x, -YARD.y), Color(0.22, 0.24, 0.26), 0.6)

	# painted lane markings
	var lane := Color(0.72, 0.62, 0.30, 0.20)
	for i in 9:
		var y := -YARD.y + 3.0 + i * 3.6
		draw_line(Vector2(-YARD.x + 2, y), Vector2(YARD.x - 2, y), lane, 0.06)

	# rain: short streaks, screen-space-ish but anchored in the world
	var streak := Color(0.55, 0.62, 0.70, 0.22)
	for r in _rain:
		var x: float = fposmod(r.x + _t * 2.2 + r.z, YARD.x * 1.2) - YARD.x * 0.6
		var y: float = fposmod(r.y + _t * r.z, YARD.y * 1.2) - YARD.y * 0.6
		draw_line(Vector2(x, y), Vector2(x - 0.18, y + 0.55), streak, 0.045)


func _ground() -> void:
	pass  # slab painted in _draw


func _containers() -> void:
	var palette := [RUST, Color(0.16, 0.30, 0.38), Color(0.28, 0.30, 0.22), Color(0.22, 0.24, 0.26), Color(0.42, 0.26, 0.14)]
	var rows := 6
	var cols := 7
	for r in rows:
		for c in cols:
			if _rng.randf() < 0.26:
				continue
			var long := _rng.randf() < 0.5
			var size := Vector2(2.2, 5.4 if long else 3.0)
			var pos := Vector2(-16.0 + c * 5.2 + _rng.randf_range(-0.4, 0.4),
				-10.0 + r * 5.0 + _rng.randf_range(-0.4, 0.4))
			if absf(pos.x) < 3.0 and absf(pos.y) < 16.0:
				continue  # keep the middle corridor walkable
			_box(pos, size, palette[_rng.randi() % palette.size()])


func _box(pos: Vector2, size: Vector2, color: Color) -> void:
	var body := StaticBody2D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0

	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)

	var poly := Polygon2D.new()
	var h := size * 0.5
	poly.polygon = PackedVector2Array([
		Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y),
	])
	poly.color = color
	body.add_child(poly)

	# a lighter top edge so the boxes read as solid
	var edge := Line2D.new()
	edge.width = 0.08
	edge.default_color = Color(1, 1, 1, 0.10)
	edge.add_point(Vector2(-h.x, -h.y))
	edge.add_point(Vector2(h.x, -h.y))
	body.add_child(edge)
	add_child(body)


func _relays() -> void:
	var spots := [Vector2(-14, -4), Vector2(14, -8), Vector2(2, -18)]
	for i in spots.size():
		var r = load("res://src2d/relay2d.gd").new()
		add_child(r)
		r.position = spots[i]
		r.setup(i)
		relays.append(r)


func _extraction() -> void:
	var marker := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(extraction_pos + Vector2(cos(a), sin(a)) * 2.2)
	marker.polygon = pts
	marker.color = Color(0.20, 0.55, 0.85, 0.22)
	add_child(marker)

	var ring := Line2D.new()
	ring.width = 0.12
	ring.default_color = Color(0.35, 0.70, 1.0, 0.55)
	for i in 25:
		var a := TAU * i / 24.0
		ring.add_point(extraction_pos + Vector2(cos(a), sin(a)) * 2.2)
	add_child(ring)


func _spawn_points() -> void:
	enemy_spawns = [
		Vector2(-12, -6), Vector2(12, -4), Vector2(-6, -14),
		Vector2(8, -16), Vector2(-16, 2), Vector2(16, 4),
	]


func spawn_enemies(parent: Node) -> void:
	for p in enemy_spawns:
		var e = load("res://src2d/enemy2d.gd").new()
		parent.add_child(e)
		e.position = p
