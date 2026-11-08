class_name NavWorld
extends RefCounted
## Godot's own navigation (NavigationMesh + NavigationServer3D) for the cat, the owner and the dog:
## the walkable floor is baked at runtime from the real furniture colliders, so paths are smooth lines that hug
## corners instead of zig-zags over 20 cm cells. Hiding spots (under tables, chairs, sofas) are cut out, exactly as
## the old grid blocked them, so nobody walks in to a hidden rat. The grid (NavGrid) stays for the yes/no questions
## (is this point free, pick a random free point) and as a fallback while the map is not ready yet.

const RADIUS := 0.12   # how far bodies keep off furniture (the grid's half cell + inflate)
const HEIGHT := 0.42   # anything lower than this over the floor blocks (chair seats at 45 cm don't)

var map: RID
var region: RID
var mesh: NavigationMesh


func _init(game: Node3D, no_go: Array) -> void:
	mesh = NavigationMesh.new()
	mesh.cell_size = 0.04
	mesh.cell_height = 0.02
	mesh.agent_radius = RADIUS
	mesh.agent_height = HEIGHT
	mesh.agent_max_climb = 0.04
	mesh.agent_max_slope = 20.0
	mesh.region_min_size = 1.0
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1
	var o := Nights.world(0, 0)
	var w := Nights.ROOM_W / 100.0
	var d := Nights.ROOM_D / 100.0
	mesh.filter_baking_aabb = AABB(o + Vector3(-0.3, -0.2, -0.3), Vector3(w + 0.6, HEIGHT + 0.4, d + 0.6))
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, src, game)
	for z in no_go:
		var zn := z as Zone
		var hx := zn.size.x * 0.5 + 0.03
		var hz := zn.size.z * 0.5 + 0.03
		var pts := PackedVector3Array()
		for c in [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]:
			pts.append(zn.to_global(c))
		src.add_projected_obstruction(pts, -0.1, HEIGHT + 0.2, false)
	NavigationServer3D.bake_from_source_geometry_data(mesh, src)
	_floor_only()
	if OS.has_environment("NAVDUMP"):
		var polys := []
		for i in mesh.get_polygon_count():
			polys.append(Array(mesh.get_polygon(i)))
		var vs := []
		for v in mesh.vertices:
			vs.append([v.x, v.z])
		var zs := []
		for z in no_go:
			zs.append([(z as Zone).global_position.x, (z as Zone).global_position.z, (z as Zone).size.x, (z as Zone).size.z, (z as Zone).global_rotation.y])
		var f := FileAccess.open(OS.get_environment("NAVDUMP"), FileAccess.WRITE)
		f.store_string(JSON.stringify({"v": vs, "p": polys, "z": zs}))
	map = game.get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, mesh.cell_size)
	NavigationServer3D.map_set_cell_height(map, mesh.cell_height)
	NavigationServer3D.map_set_use_edge_connections(map, false)
	region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region, map)
	NavigationServer3D.region_set_navigation_mesh(region, mesh)


## Keep only the floor: tops of counters, the fridge and low furniture get baked as walkable islands too.
func _floor_only() -> void:
	var vs := mesh.vertices
	var keep := []
	for i in mesh.get_polygon_count():
		var poly := mesh.get_polygon(i)
		var y := 0.0
		for j in poly:
			y += vs[j].y
		if y / poly.size() < 0.08:
			keep.append(poly)
	# then only the biggest connected piece (floor pockets boxed in by furniture are unreachable anyway)
	var by_vert := {}
	for i in keep.size():
		for j in keep[i]:
			var k := _vkey(vs[j])
			if not by_vert.has(k):
				by_vert[k] = []
			by_vert[k].append(i)
	var comp := []
	comp.resize(keep.size())
	comp.fill(-1)
	var areas := []
	for i in keep.size():
		if comp[i] != -1:
			continue
		var c := areas.size()
		var area := 0.0
		var stack := [i]
		comp[i] = c
		while not stack.is_empty():
			var q: int = stack.pop_back()
			var poly: PackedInt32Array = keep[q]
			for t in range(1, poly.size() - 1):
				var a := vs[poly[0]]
				area += absf((vs[poly[t]] - a).cross(vs[poly[t + 1]] - a).y) * 0.5
			for j in poly:
				for n in by_vert[_vkey(vs[j])]:
					if comp[n] == -1:
						comp[n] = c
						stack.append(n)
		areas.append(area)
	var best := 0
	for c in areas.size():
		if areas[c] > areas[best]:
			best = c
	mesh.clear_polygons()
	for i in keep.size():
		if comp[i] == best:
			mesh.add_polygon(keep[i])


static func _vkey(v: Vector3) -> Vector2i:
	return Vector2i(roundi(v.x * 100.0), roundi(v.z * 100.0))


func ready() -> bool:
	return NavigationServer3D.map_get_iteration_id(map) > 0


## Shortest smooth path from a to b on the floor (without the start point). Empty if the map isn't ready.
func find_path(a: Vector3, b: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if not ready():
		return out
	var pts := NavigationServer3D.map_get_path(map, a, b, true)
	for i in range(1, pts.size()):
		out.append(pts[i])
	return out


## Is the point on the walkable floor (within tol)?
func on_mesh(p: Vector3, tol := 0.03) -> bool:
	if not ready():
		return true
	var c := NavigationServer3D.map_get_closest_point(map, p)
	return Vector2(c.x - p.x, c.z - p.z).length() <= tol


func dispose() -> void:
	if region.is_valid():
		NavigationServer3D.free_rid(region)
