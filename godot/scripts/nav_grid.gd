class_name NavGrid
extends RefCounted
## A* on a 20 cm grid over the room, like the prototype: cells under furniture legs, walls and hiding spots
## (under tables, chairs, sofas) are blocked, so the cat and the owner walk around them and can't reach a hidden rat.

const CELL := 0.2
var gw := 48
var gh := 30
var astar := AStarGrid2D.new()
var origin := Vector3.ZERO


func _init(game: Game, no_go: Array, inflate := 0.07) -> void:
	gw = roundi(Nights.ROOM_W / 100.0 / CELL)
	gh = roundi(Nights.ROOM_D / 100.0 / CELL)
	origin = Nights.world(0, 0)
	astar.region = Rect2i(0, 0, gw, gh)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	var half := Vector3(CELL / 2.0 + inflate, 0.18, CELL / 2.0 + inflate)
	for y in gh:
		for x in gw:
			var c := cell_center(x, y)
			var b := x == 0 or y == 0 or x == gw - 1 or y == gh - 1
			if not b:
				b = not game.box_free(c + Vector3.UP * 0.24, half)
			if not b:
				for z in no_go:
					if (z as Zone).contains_xz(c, inflate + 0.05):
						b = true
						break
			astar.set_point_solid(Vector2i(x, y), b)


func cell_center(x: int, y: int) -> Vector3:
	return origin + Vector3((x + 0.5) * CELL, 0.0, (y + 0.5) * CELL)


func to_cell(p: Vector3) -> Vector2i:
	return Vector2i(clampi(floori((p.x - origin.x) / CELL), 0, gw - 1), clampi(floori((p.z - origin.z) / CELL), 0, gh - 1))


func blocked(x: int, y: int) -> bool:
	return x < 0 or y < 0 or x >= gw or y >= gh or astar.is_point_solid(Vector2i(x, y))


func blocked_at(p: Vector3) -> bool:
	var c := to_cell(p)
	return blocked(c.x, c.y)


func nearest_free(c: Vector2i) -> Vector2i:
	if not blocked(c.x, c.y):
		return c
	for r in range(1, 12):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if (absi(dx) == r or absi(dy) == r) and not blocked(c.x + dx, c.y + dy):
					return Vector2i(c.x + dx, c.y + dy)
	return c


func free_point(p: Vector3) -> Vector3:
	var c := nearest_free(to_cell(p))
	return cell_center(c.x, c.y)


func line_clear(a: Vector3, b: Vector3) -> bool:
	var n := ceili(a.distance_to(b) / 0.06)
	for i in range(1, n + 1):
		if blocked_at(a.lerp(b, float(i) / n)):
			return false
	return true


func random_free(min_dist: float, from: Vector3) -> Vector3:
	for t in 200:
		var x := randi_range(0, gw - 1)
		var y := randi_range(0, gh - 1)
		if blocked(x, y):
			continue
		var p := cell_center(x, y)
		if p.distance_to(from) >= min_dist:
			return p
	return free_point(Vector3.ZERO)


## Shortest path (smoothed) from a to b as world points on the floor; empty if unreachable.
func find_path(a: Vector3, b: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var s := nearest_free(to_cell(a))
	var t := nearest_free(to_cell(b))
	if s == t:
		out.append(cell_center(t.x, t.y))
		return out
	var ids := astar.get_id_path(s, t)
	if ids.is_empty():
		return out
	var anchor := cell_center(s.x, s.y)
	for i in range(1, ids.size()):
		var p := cell_center(ids[i].x, ids[i].y)
		var last := i == ids.size() - 1
		if last or not line_clear(anchor, cell_center(ids[i + 1].x, ids[i + 1].y)):
			out.append(p)
			anchor = p
	return out
