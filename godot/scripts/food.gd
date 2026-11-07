class_name Food
extends Node3D
## Food the rat picks up by walking over it, or a find (secret) that sets a flag. Like the prototype: a crumb weighs 1
## and is worth 1, a cheese weighs 2 and is worth 5, big food (sausage, chicken…) weighs 3, is worth 6 and is dragged.

const BIG := ["sausage", "chicken", "pizza", "cake", "potato", "fat", "biscuit", "salami"]

var type := "crumb"
var id := ""
var hidden := false
var poison := false
var is_find := false
var label := ""
var carried := false
var reveal_t := 0.0


func big() -> bool: return BIG.has(type)
func is_cheese() -> bool: return not is_find and type != "crumb"
func weight() -> int: return 0 if is_find else (3 if big() else (1 if type == "crumb" else 2))
func value() -> int: return 0 if (is_find or poison) else (6 if big() else (1 if type == "crumb" else 5))


func make_poison() -> void:
	poison = true
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i)
			if mat is BaseMaterial3D:
				var c := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				c.albedo_color = c.albedo_color.lerp(Settings.poison_color(), 0.65)
				m.set_surface_override_material(i, c)


func _process(dt: float) -> void:
	if reveal_t > 0.0:
		reveal_t -= dt
	if not carried and visible:
		rotate_y(0.5 * dt)


static func model_for(t: String) -> String:
	match t:
		"crumb": return "food/crumb"
		"sausage", "salami": return "food/sausage"
		"chicken": return "food/chicken_leg"
		"pizza": return "food/pizza_slice"
		"cake": return "food/cake_slice"
		"potato": return "food/potato"
		"fat": return "food/lard"
		"biscuit", "treat": return "food/dog_biscuit"
		"cookie": return "food/cookie"
		"kibble": return "food/kibble"
		"rusk": return "food/rusk"
	return "food/cheese"
