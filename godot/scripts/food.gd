class_name Food
extends Node3D
## Food the rat picks up by walking over it, or a find (secret) that sets a flag. Like the prototype: a crumb weighs 1
## and is worth 1, a cheese weighs 2 and is worth 5, big food (sausage, chicken…) weighs 3, is worth 6 and is dragged.

const BIG := ["sausage", "chicken", "pizza", "cake", "potato", "fat", "biscuit", "salami"]
## Round 5: no crumbs — she collects PIECES of real food. "crumb" in night data is remapped to
## one of these at spawn (see game.spawn_food): a cheese wedge, a pizza slice, a rusk chunk.
const LIGHT := ["crumb", "wedge", "slice", "chunk"]
const PIECES := ["wedge", "slice", "chunk"]

var type := "crumb"
var wscale := 1.0  # world scale for this type (set at spawn; small food used to be unreadable)
var id := ""
var hidden := false
var poison := false
var is_find := false
var label := ""
var carried := false
var reveal_t := 0.0


func big() -> bool: return BIG.has(type)
func is_cheese() -> bool: return not is_find and type != "crumb"
func weight() -> int: return 0 if is_find else (3 if big() else (1 if LIGHT.has(type) else 2))
func value() -> int: return 0 if (is_find or poison) else (6 if big() else (1 if type == "crumb" else (2 if LIGHT.has(type) else 5)))


## Floor presence per type: pieces and small foods sit bigger than life so they READ as food.
static func world_scale(t: String) -> float:
	match t:
		"wedge": return 0.62
		"slice": return 0.55
		"chunk": return 0.85
		"crumb": return 0.9
	if BIG.has(t):
		return 1.12
	return 1.22


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


## Fling this food sideways off whatever it was on: an arc to a floor point 0.35–0.55 m to the
## side, so a dropped sausage never wedges at a table's base (round 5, playtest: it stuck there).
func toss_scatter() -> void:
	var from := global_position
	var space := get_world_3d().direct_space_state
	# round 14 (playtest, night 8: a tossed chicken leg VANISHED): the old code
	# took the first sideways point blind — if it lay inside a wall or a solid
	# counter, the down-ray found nothing there and the food froze mid-geometry.
	# Now: try several directions, accept only a hit on a real top face at or
	# below where the food was; last resort, drop it straight down at her feet.
	var at := from
	for k in 7:
		var cand := from if k == 6 else from + Vector3(cos(randf() * TAU), 0, sin(randf() * TAU)) * randf_range(0.35, 0.55)
		var q := PhysicsRayQueryParameters3D.create(cand + Vector3.UP * 0.5, cand + Vector3.DOWN * 3.0)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and (hit.normal as Vector3).y > 0.65 and (hit.position as Vector3).y <= from.y + 0.05:
			at = hit.position
			break
	set_meta("dropped_at", at)
	var tw := create_tween()
	tw.tween_method(func(t: float): global_position = from.lerp(at, t) + Vector3.UP * sin(t * PI) * 0.16, 0.0, 1.0, 0.38)
	tw.tween_callback(func(): rotation = Vector3(0, randf() * TAU, 0))


func _process(dt: float) -> void:
	if reveal_t > 0.0:
		reveal_t -= dt
	if not carried and visible:
		rotate_y(0.5 * dt)


static func model_for(t: String) -> String:
	match t:
		"wedge": return "food/cheese"
		"slice": return "food/pizza_slice"
		"chunk": return "food/rusk"
		"crumb": return "food/rusk"
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
