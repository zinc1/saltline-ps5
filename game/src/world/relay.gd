extends StaticBody3D
## An uplink relay: amber while live, dead red once cut.

var lamp: MeshInstance3D
var glow: OmniLight3D
var cut := false


func mark_cut() -> void:
	if cut:
		return
	cut = true
	var dead := Color(0.45, 0.08, 0.06)
	if lamp:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = dead
		mat.emission_enabled = true
		mat.emission = dead
		mat.emission_energy_multiplier = 0.6
		lamp.material_override = mat
	if glow:
		glow.light_color = dead
		glow.light_energy = 0.35
		glow.omni_range = 3.5
	# collapse the mast a little so it reads as disabled
	var tween := create_tween()
	tween.tween_property(self, "rotation_degrees:z", 6.0, 0.35)
