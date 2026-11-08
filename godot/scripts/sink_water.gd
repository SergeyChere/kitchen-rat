class_name SinkWater
extends Zone
## Water in the kitchen sink. A rat that falls or jumps in swims (slowly) and must climb out over the edge
## (Space facing the side) before she runs out of breath; if she doesn't, it counts as being caught.

var level := 0.0   # world height of the water surface
var _mesh: MeshInstance3D
var _t := 0.0


func setup(surface_y: float) -> void:
	level = surface_y
	_mesh = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size.x, size.z)
	_mesh.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.35, 0.65, 0.95, 0.62)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	m.roughness = 0.15
	m.rim_enabled = true
	m.rim = 0.6
	m.emission_enabled = true
	m.emission = Color(0.12, 0.25, 0.4)
	_mesh.material_override = m
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_mesh.global_position = Vector3(global_position.x, level, global_position.z)


func _process(dt: float) -> void:
	_t += dt
	if _mesh:
		_mesh.global_position.y = level + sin(_t * 2.0) * 0.0015  # a gentle lap


func stay(rat: Rat, _dt: float) -> void:
	if rat.water == null and not rat.jumping and rat.global_position.y < level + 0.02:
		rat.start_swim(self)
