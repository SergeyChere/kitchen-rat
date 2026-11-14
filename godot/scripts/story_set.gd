class_name StorySet
extends Node3D
## Round 17: the places of the prologue that are not in the house, now painted (the player's own pictures in
## assets/story/: the garden in the rain, the hole at the foot of the wall, the passage inside the wall, the burrow
## behind the kitchen). Each is a stage far off to the side of the room: a fixed camera, the painting behind
## everything as a backdrop filling its view, and an empty ground the rat and the street cat run on. A point on
## the painting (say, the hole) is found on that ground by casting the camera's ray through it, so the 3D
## animals line up with the painted trail, hole and doorway. Built while the prologue plays, freed after it.

## stage: painting, camera height above the ground (m), its pitch (degrees, + = up), field of view, and the
## light on the animals (colour, energy) to sit them in the painting
const STAGES := {
	"garden": {"tex": "res://assets/story/garden.jpg", "h": 0.84, "pitch": 5.3, "fov": 50.0, "light": Color(0.95, 0.8, 0.6), "e": 1.3},
	"hole": {"tex": "res://assets/story/hole.jpg", "h": 0.15, "pitch": 0.0, "fov": 50.0, "light": Color(1.0, 0.75, 0.48), "e": 1.1},
	"passage": {"tex": "res://assets/story/passage.jpg", "h": 0.085, "pitch": 4.0, "fov": 55.0, "light": Color(0.95, 0.72, 0.5), "e": 0.8},
	"burrow": {"tex": "res://assets/story/burrow.jpg", "h": 0.09, "pitch": 6.0, "fov": 55.0, "light": Color(1.0, 0.82, 0.55), "e": 1.2},
}

var rain: CPUParticles3D
var _base := {}  # stage → its origin far off to the side
var _backdrop: MeshInstance3D


func build() -> void:
	name = "Story set"
	var i := 0
	for k in STAGES:
		_base[k] = Vector3(60.0 + i * 40.0, 0.0, 0.0)
		var st: Dictionary = STAGES[k]
		var l := OmniLight3D.new()
		add_child(l)
		l.global_position = _base[k] + Vector3(0.6, 0.9, -0.4)
		l.light_color = st.light
		l.light_energy = st.e
		l.omni_range = 6.0
		i += 1
	rain = CPUParticles3D.new()
	rain.amount = 500
	rain.lifetime = 0.5
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(1.6, 0.1, 1.6)
	rain.direction = Vector3(0.12, -1, 0.0)
	rain.spread = 2.0
	rain.gravity = Vector3(0, -9.8, 0)
	rain.initial_velocity_min = 5.0
	rain.initial_velocity_max = 6.5
	var streak := QuadMesh.new()
	streak.size = Vector2(0.004, 0.11)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0.8, 0.86, 1.0, 0.3)
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	streak.material = sm
	rain.mesh = streak
	rain.local_coords = false
	rain.emitting = false
	add_child(rain)


## The camera's place on a stage: [position, a point it looks at].
func cam(stage: String) -> Array:
	var st: Dictionary = STAGES[stage]
	var p: Vector3 = _base[stage] + Vector3(0, float(st.h), 0)
	var look := p + Vector3(0, tan(deg_to_rad(float(st.pitch))) * 10.0, -10.0)
	return [p, look]


## The ground point under a point of the painting (u, v from its top-left, 0…1), for a screen of `aspect`.
func ground(stage: String, u: float, v: float, aspect: float) -> Vector3:
	var st: Dictionary = STAGES[stage]
	var c := cam(stage)
	var b := Basis.looking_at((c[1] as Vector3) - (c[0] as Vector3), Vector3.UP)
	var t := tan(deg_to_rad(float(st.fov)) * 0.5)
	var pa := _paint_aspect(stage)
	# the painting covers the screen: on a screen wider than it, its top and bottom are cut off, and so on
	var su := u
	var sv := v
	if aspect > pa:
		sv = 0.5 + (v - 0.5) * aspect / pa
	else:
		su = 0.5 + (u - 0.5) * pa / aspect
	var d := b * Vector3((su * 2.0 - 1.0) * t * aspect, (1.0 - sv * 2.0) * t, -1.0)
	if d.y > -0.0001:
		d.y = -0.0001
	var k := -float(st.h) / d.y
	return (c[0] as Vector3) + d * k


func _paint_aspect(stage: String) -> float:
	var tex := load(STAGES[stage].tex) as Texture2D
	return float(tex.get_width()) / float(tex.get_height()) if tex else 16.0 / 9.0


## Hangs the stage's painting behind everything the camera sees (the backdrop rides on the camera).
func show_backdrop(camera: Camera3D, stage: String, aspect: float) -> void:
	if _backdrop == null:
		_backdrop = MeshInstance3D.new()
		_backdrop.mesh = QuadMesh.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.disable_fog = true
		m.disable_receive_shadows = true
		_backdrop.material_override = m
		_backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _backdrop.get_parent() != camera:
		if _backdrop.get_parent():
			_backdrop.get_parent().remove_child(_backdrop)
		camera.add_child(_backdrop)
	var st: Dictionary = STAGES[stage]
	var dist := 80.0
	var hgt := 2.0 * dist * tan(deg_to_rad(float(st.fov)) * 0.5)
	var pa := _paint_aspect(stage)
	var size := Vector2(hgt * pa, hgt) if aspect <= pa else Vector2(hgt * aspect, hgt * aspect / pa)
	(_backdrop.mesh as QuadMesh).size = size
	_backdrop.position = Vector3(0, 0, -dist)
	_backdrop.rotation = Vector3.ZERO
	(_backdrop.material_override as StandardMaterial3D).albedo_texture = load(st.tex)
	(_backdrop.material_override as StandardMaterial3D).albedo_color = Color.WHITE
	_backdrop.visible = true


func hide_backdrop() -> void:
	if _backdrop:
		_backdrop.visible = false


## A lightning flash on the painting.
func flash(k: float) -> void:
	if _backdrop and _backdrop.visible:
		(_backdrop.material_override as StandardMaterial3D).albedo_color = Color.WHITE * (1.0 + 0.9 * k)


func _exit_tree() -> void:
	if is_instance_valid(_backdrop):
		_backdrop.queue_free()
