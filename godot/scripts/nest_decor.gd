class_name NestDecor
## Round 17 (asked: "everything she drags into the burrow that isn't food decorates it — and we choose where it
## goes"). The finds she carries home (a button, a thimble, a toy mouse, a sock…) are kept for good and hung or
## set down at one of the burrow's spots, which the player picks at the end of the night. Saved in Progress.decor
## as slot → kind, and shown in every burrow scene from then on.

## The spots, in room cm (x, y, height above the burrow floor), how the thing sits there, and a name for the
## buttons, named as seen from the hole looking in. The burrow is x 5…255, y 608…785 (back wall at 785), 95 cm high; the bed of twigs is at (90, 725).
const SLOTS := [
	{"at": Vector3(45, 776, 46), "how": "wall_back", "name": "Back wall, right"},
	{"at": Vector3(135, 776, 58), "how": "wall_back", "name": "Above the bed"},
	{"at": Vector3(220, 776, 46), "how": "wall_back", "name": "Back wall, left"},
	{"at": Vector3(12, 660, 44), "how": "wall_west", "name": "Right wall, front"},
	{"at": Vector3(12, 735, 52), "how": "wall_west", "name": "Right wall, back"},
	{"at": Vector3(248, 665, 44), "how": "wall_east", "name": "Left wall, front"},
	{"at": Vector3(248, 740, 52), "how": "wall_east", "name": "Left wall, back"},
	{"at": Vector3(135, 700, 84), "how": "hang", "name": "Hanging from the roof"},
	{"at": Vector3(205, 650, 84), "how": "hang", "name": "Hanging by the door"},
	{"at": Vector3(205, 715, 0), "how": "floor", "name": "Floor, by the pups"},
	{"at": Vector3(232, 765, 0), "how": "floor", "name": "Floor, back corner"},
	{"at": Vector3(40, 765, 0), "how": "floor", "name": "Floor, behind the bed"},
]

const NAMES := {"button": "button", "sock": "sock", "photo": "old photo", "toy": "toy mouse", "thimble": "thimble",
	"ring": "gold ring", "drawing": "kid’s drawing", "letter": "letter", "candle": "birthday candle",
	"marble": "glass marble", "battery": "battery", "bottle_cap": "bottle cap", "key": "key", "earring": "earring",
	"whistle": "party whistle", "cufflink": "cufflink", "toy_car": "toy car", "toy_dino": "toy dinosaur",
	"silver_spoon": "silver spoon", "chew_toy": "chew toy", "dino": "toy dinosaur", "car": "toy car"}


static func model_for(kind: String) -> String:
	var m := {"toy": "toy_mouse", "dino": "toy_dino", "car": "toy_car", "cap": "bottle_cap", "spoon": "silver_spoon"}.get(kind, kind) as String
	return "finds/" + m if ResourceLoader.exists(LevelBuilder.MODELS + "finds/" + m + ".glb") else "finds/button"


static func label(kind: String) -> String:
	return NAMES.get(kind, kind.replace("_", " "))


static func free_slots() -> Array:
	var out := []
	for i in SLOTS.size():
		if not Progress.decor.has(str(i)):
			out.append(i)
	return out


## Puts one thing at a spot under `parent` (the burrow). Wall things lean on the wall facing in, hanging things
## dangle on a thread, floor things just sit.
static func place(b: LevelBuilder, parent: Node3D, slot: int, kind: String) -> Node3D:
	var s: Dictionary = SLOTS[slot]
	var p: Vector3 = s.at
	var at := Nights.world(p.x, p.y, p.z)
	var holder := Node3D.new()
	holder.name = "Decor %d" % slot
	parent.add_child(holder)
	holder.global_position = at
	var how := str(s.how)
	holder.rotation.y = {"wall_back": PI, "wall_west": PI * 0.5, "wall_east": -PI * 0.5}.get(how, randf() * TAU)
	var m := b.spawn(model_for(kind), at, 0.0, holder)
	if m == null:
		return holder
	m.position = Vector3.ZERO
	m.rotation = Vector3.ZERO
	# finds are life-size for a person: a button would be a speck on a burrow wall — shown a little larger
	var size := LevelBuilder.world_aabb(m).size
	var longest := maxf(size.x, maxf(size.y, size.z))
	var want := 0.11 if how in ["floor"] else 0.1
	if longest > 0.0001:
		m.scale *= clampf(want / longest, 0.6, 4.0)
	if how.begins_with("wall"):
		m.rotation.x = -PI * 0.5 if size.y < size.x * 0.4 else 0.0  # a flat thing (a photo, a button) faces out
		m.position.z = 0.012
	elif how == "hang":
		var thread := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = 0.0012
		cy.bottom_radius = 0.0012
		cy.height = 0.1
		thread.mesh = cy
		thread.material_override = b.mat(Color(0.78, 0.72, 0.6))
		holder.add_child(thread)
		thread.position = Vector3(0, 0.06, 0)
	for mi in holder.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return holder


## Every saved decoration, set up in a freshly built burrow.
static func build_all(b: LevelBuilder, parent: Node3D) -> void:
	for k in Progress.decor:
		var i := int(k)
		if i >= 0 and i < SLOTS.size():
			place(b, parent, i, str(Progress.decor[k]))
