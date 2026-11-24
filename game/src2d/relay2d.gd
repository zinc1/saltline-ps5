extends StaticBody2D
## An uplink relay: amber while live, dead red once cut. `cut()` is what the
## breacher's interact key calls.

var relay_index := 0
var cut_done := false

var _lamp: Polygon2D
var _mast: Polygon2D


func setup(index: int) -> void:
	relay_index = index
	add_to_group("relay")
	set_meta("relay_index", index)
	set_meta("cut", false)
	collision_layer = 1
	collision_mask = 0

	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 0.55
	cs.shape = shape
	add_child(cs)

	_mast = Polygon2D.new()
	_mast.polygon = PackedVector2Array([
		Vector2(-0.34, -0.34), Vector2(0.34, -0.34), Vector2(0.34, 0.34), Vector2(-0.34, 0.34),
	])
	_mast.color = Color(0.26, 0.28, 0.30)
	add_child(_mast)

	_lamp = Polygon2D.new()
	_lamp.polygon = PackedVector2Array([
		Vector2(-0.16, -0.16), Vector2(0.16, -0.16), Vector2(0.16, 0.16), Vector2(-0.16, 0.16),
	])
	_lamp.color = Color(1.0, 0.70, 0.28)
	add_child(_lamp)


func cut() -> void:
	if cut_done:
		return
	cut_done = true
	set_meta("cut", true)
	if _lamp:
		_lamp.color = Color(0.42, 0.09, 0.07)
	if _mast:
		_mast.color = Color(0.18, 0.19, 0.20)
	Game.cut_relay(relay_index)
