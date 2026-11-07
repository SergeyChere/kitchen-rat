class_name Nights
## Night data exported from game/js/levels.js by tools/export_nights.mjs (res://data/nights/NN_id.json).
## Positions in the data are the prototype's room coordinates in cm: x to the east, y to the south,
## origin at the north-west corner. Godot: x east, z south, y up, 1 unit = 1 m.

const ROOM_W := 960.0
const ROOM_D := 600.0
## Nights whose room is built so far (they all take place in the kitchen).
const BUILT := ["kitchen", "kitchen2", "water", "party", "vacuum"]


static func world(x: float, y: float, h: float = 0.0) -> Vector3:
	return Vector3((x - ROOM_W / 2.0) / 100.0, h / 100.0, (y - ROOM_D / 2.0) / 100.0)


## A [x, y] pair from the data → world position (Vector3.ZERO when missing).
static func pos(p, h: float = 0.0) -> Vector3:
	if p is Array and p.size() >= 2:
		return world(float(p[0]), float(p[1]), h)
	return Vector3.ZERO


## A prototype angle (radians, x east / y south) → a direction.
static func dir(a: float) -> Vector3:
	return Vector3(cos(a), 0.0, sin(a))


## Yaw that turns a model (which faces +Z) toward dir.
static func yaw_to(d: Vector3) -> float:
	return atan2(d.x, d.z)


static func files() -> PackedStringArray:
	var out := PackedStringArray()
	var f := FileAccess.open("res://data/nights/index.txt", FileAccess.READ)
	if f == null:
		return out
	for line in f.get_as_text().split("\n"):
		if line.strip_edges() != "":
			out.append(line.strip_edges())
	return out


## Load a night by id ("kitchen", "water"…) or by number ("1".."20").
static func load_night(id: String) -> Dictionary:
	for f in files():
		var num := f.get_slice("_", 0)
		var fid := f.substr(num.length() + 1)
		if fid != id and num.lstrip("0") != id:
			continue
		var txt := FileAccess.get_file_as_string("res://data/nights/" + f + ".json")
		var d = JSON.parse_string(txt)
		if d is Dictionary:
			return d
	push_warning("Kitchen Rat: night '%s' not found" % id)
	return {"id": id, "name": id, "number": 0, "goal": 10, "seconds": 600.0}


static func threat_star(night: Dictionary, t: String) -> int:
	var i: int = (night.get("threats", []) as Array).find(t)
	return 99 if i < 0 else i + 1
