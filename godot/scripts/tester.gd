class_name Tester
extends RefCounted
## Scripted checks for headless runs: godot --path godot -- --night=kitchen --auto --test=walk
## Prints PASS/FAIL lines; used by the developer, not part of the game.

var g: Game
var name := ""


func _init(game: Game, test: String) -> void:
	g = game
	name = test


func start(host: Node) -> void:
	_run(host)


func _wait(host: Node, sec: float) -> void:
	await host.get_tree().create_timer(sec).timeout


func _check(label: String, ok: bool, info := "") -> void:
	print(("PASS " if ok else "FAIL ") + label + ("" if info == "" else "  (" + info + ")"))


func _run(host: Node) -> void:
	if name == "cat":
		await _cat(host)
		return
	if name == "owner":
		await _owner(host)
		return
	if name == "hides":
		await _hides(host)
		return
	if name == "watchvac":
		for i in 10:
			await _wait(host, 2.0)
			var v := g.vacuum
			print("t %.0f vac %s on %s vis %s path %d stun %.1f rat %s" % [g.night_time, str(v.global_position), v.on, v.visible, v.path.size(), v._stun, str(g.rat.global_position)])
		host.get_tree().quit()
		return
	if name == "climb":
		var r := g.rat
		await _wait(host, 0.5)
		# up a table leg: the table top (75 cm) is too high to jump onto
		r.teleport(Nights.world(720, 528, 1), Nights.yaw_to(Vector3.FORWARD))
		g.cam.snap(r.rotation.y)
		await _wait(host, 0.4)
		_check("no jump onto the table from the floor", not r.has_jump_target())
		await _press(host, "jump")
		await _wait(host, 1.8)
		_check("climbed up the table leg onto the table", r.surface_id == "table", "surface " + r.surface_id + " y %.2f" % r.global_position.y)
		# walk off the north edge (not running): she climbs down
		r.teleport(Nights.world(700, 395, 76), Nights.yaw_to(Vector3.FORWARD))
		g.cam.snap(r.rotation.y)
		await _wait(host, 0.3)
		Input.action_press("forward")
		var saw := false
		for i in 20:
			await _wait(host, 0.1)
			if r.jumping and r._kind == "descend": saw = true
		Input.action_release("forward")
		await _wait(host, 1.0)
		_check("walking off the table she climbs down", saw and r.global_position.y < 0.05, "y %.2f" % r.global_position.y)
		# a hop that falls short of the chair seat: she grabs the edge and pulls up
		r.teleport(Nights.world(634, 420, 1), Nights.yaw_to(Vector3.LEFT))
		await _wait(host, 0.3)
		r.velocity = Vector3(-0.9, 1.7, 0)
		r._hopping = true
		await _wait(host, 1.4)
		_check("a short hop grabs the chair edge and climbs up", r.surface_id == "chair", "surface " + r.surface_id + " y %.2f" % r.global_position.y)
		host.get_tree().quit()
		return
	if name == "show":  # a video of the new climbing, sniffing and carrying
		var r := g.rat
		await _wait(host, 0.4)
		r.teleport(Nights.world(720, 545, 1), Nights.yaw_to(Vector3.FORWARD))
		g.cam.snap(r.rotation.y)
		Input.action_press("forward")
		await _wait(host, 0.35)
		Input.action_release("forward")
		await _press(host, "jump")
		await _wait(host, 2.0)
		g.cam.snap(r.rotation.y)
		Input.action_press("forward")
		await _wait(host, 2.2)
		Input.action_release("forward")
		await _wait(host, 0.4)
		Input.action_press("sniff")
		await _wait(host, 2.6)
		Input.action_release("sniff")
		var f := g.spawn_food("cheese", r.global_position, "", false)
		r.carry(f)
		g.cam.snap(r.rotation.y + PI * 0.5)
		Input.action_press("left")
		await _wait(host, 1.2)
		Input.action_release("left")
		await _press(host, "drop")
		await _wait(host, 1.2)
		var f2 := g.spawn_food("cheese", r.global_position, "", false)
		r.teleport(Nights.world(180, 560, 1), PI)
		r.carry(f2)
		g.cam.snap(0.0)
		Input.action_press("back")
		await _wait(host, 1.6)
		Input.action_release("back")
		await _wait(host, 1.6)
		host.get_tree().quit()
		return
	if name == "feel":  # a little run for a video of the movement
		var r := g.rat
		r.teleport(Nights.world(300, 500, 1), PI)
		g.cam.snap(PI)
		await _wait(host, 0.5)
		Input.action_press("forward")
		await _wait(host, 1.2)
		Input.action_press("run")
		await _wait(host, 1.0)
		Input.action_press("left")
		await _wait(host, 0.8)
		Input.action_release("left")
		Input.action_release("run")
		await _press(host, "jump")
		Input.action_press("jump")
		await _wait(host, 0.4)
		Input.action_release("jump")
		await _wait(host, 0.8)
		Input.action_release("forward")
		await _wait(host, 0.6)
		await _press(host, "jump")
		await _wait(host, 1.2)
		host.get_tree().quit()
		return
	if name == "crouch":
		await _wait(host, 0.5)
		var r := g.rat
		var spot: HideSpot = null
		for z in g.zones:
			if z is HideSpot and z.id == "sofa": spot = z
		if spot == null:
			print("no sofa"); host.get_tree().quit(); return
		var up := g.ray(Vector3(spot.global_position.x, 0.01, spot.global_position.z), Vector3(spot.global_position.x, 1.0, spot.global_position.z))
		print("clearance under the sofa: ", up.get("position", "none"), " ", up.get("collider", null))
		# stand 0.5 m in front of the sofa's hiding spot (on the room side) and walk in, first upright, then sneaking
		var c := spot.global_position
		var out := Vector3(0, 0, 1) if c.z < 0.0 else Vector3(0, 0, -1)
		for sneak in [false, true]:
			r.teleport(Vector3(c.x, 0.0, c.z) + out * (spot.size.z / 2.0 + 0.35), Nights.yaw_to(-out))
			g.cam.snap(r.rotation.y)
			await _wait(host, 0.3)
			if sneak: Input.action_press("sneak")
			Input.action_press("forward")
			await _wait(host, 2.0)
			Input.action_release("forward")
			await _wait(host, 0.3)
			for hy in [0.03, 0.06, 0.09, 0.12]:
				var h2 := g.ray(r.global_position + Vector3.UP * hy, r.global_position + Vector3.UP * hy - out * 0.6)
				print("   ray fwd y", hy, ": ", h2.get("position", "none"), " ", (h2.get("collider") as Node).get_parent().name if h2.has("collider") else "")
			print("   crouched ", r.crouched, " sneaking ", r.sneaking)
			var inside := r.hidden() and r.hide_kind() == "sofa"
			_check(("sneaking she gets under the sofa" if sneak else "upright she can't get under the sofa"), inside == sneak, "hidden " + str(r.hidden()) + " at " + str(r.global_position))
			if sneak:
				Input.action_release("sneak")
				await _wait(host, 0.4)
				_check("under the sofa she stays crouched", r.crouched, "")
		host.get_tree().quit()
		return
	if name == "catjump":
		await _wait(host, 0.5)
		g._evidence = 999.0
		g.grace_t = 0.0
		var r := g.rat
		r.teleport(Nights.world(700, 445, 76), PI / 2)
		g.cat.global_position = Nights.world(720, 560)
		g.cat.mode = CatAI.Mode.WATCH
		g.cat.alert = 1.0
		g.cat._watch = 4.0
		var top := false
		for i in 40:
			await _wait(host, 0.1)
			if g.cat._top: top = true
			if i % 5 == 0: print("  cat mode ", g.cat.mode, " pos ", g.cat.global_position.snapped(Vector3.ONE * 0.01), " d ", snappedf(Vector2(g.cat.global_position.x - r.global_position.x, g.cat.global_position.z - r.global_position.z).length(), 0.01), " rat y ", snappedf(r.global_position.y, 0.01), " floor ", r.is_on_floor(), " cd ", snappedf(g.cat._jump_cd, 0.1))
		print("stars ", g.stars, " cat y ", g.cat.global_position.y, " lives ", g.lives)
		_check("at 3 stars the cat jumps up onto the table after her", top or g.lives < 3)
		g._evidence = 0.0
		host.get_tree().quit()
		return
	if name == "chairray":
		await _wait(host, 0.5)
		for x in [586, 596, 606]:
			var o := Nights.world(x, 420, 100)
			var hit := g.ray(o, o + Vector3.DOWN * 1.2)
			print("ray at ", x, ": ", hit.get("position", "none"), " ", hit.get("collider", null), " normal ", hit.get("normal", null))
		for c in g._builder.furn.get_children():
			if str(c.name).begins_with("chair"):
				for b in c.find_children("*", "CollisionShape3D", true, false):
					print(c.name, " shape ", (b as CollisionShape3D).global_position, " ", (b as CollisionShape3D).shape)
				break
		host.get_tree().quit()
		return
	if name == "islands":
		for path in ["furniture/sofa", "furniture/armchair", "furniture/bed_kid", "furniture/coffee_table"]:
			var n: Node3D = (load("res://assets/models/" + path + ".glb") as PackedScene).instantiate()
			for mi in n.find_children("*", "MeshInstance3D", true, false):
				var isl := LevelBuilder._islands((mi as MeshInstance3D).mesh)
				var txt := ""
				for i in isl: txt += " [%s %.2f]" % [str(i[0].size.snapped(Vector3.ONE * 0.01)), i[2]]
				print(path, " ", mi.name, " ", isl.size(), txt)
			n.free()
		host.get_tree().quit()
		return
	if name == "ypos":
		await _wait(host, 1.0)
		print("rat y ", g.rat.global_position.y, " floor ", g.rat.is_on_floor())
		print("rat ", g.rat.global_position, " mouth ", g.rat.mouth.global_position, " mouth scale ", g.rat.mouth.global_transform.basis.get_scale())
		var sk := g.rat.model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		print("head rest ", sk.global_transform * sk.get_bone_global_rest(sk.find_bone("Head")).origin, " head pose ", sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin)
		for mi in g.rat.model.find_children("*", "MeshInstance3D", true, false):
			print("mesh aabb ", mi.global_transform * (mi as MeshInstance3D).get_aabb(), " sk ", sk.global_transform.basis.get_scale())
		for c in g._builder.furn.get_children():
			if str(c.name).contains("upper") or c.has_meta("box_body"):
				print("furn ", c.name, " ", LevelBuilder.world_aabb(c))
		for p in g.nest_pups: print("nest pup y ", p.global_position.y)
		host.get_tree().quit()
		return
	if name == "probe":
		await _wait(host, 0.3)
		for zi in range(0, 14):
			var z := 3.35 - zi * 0.05
			var row := "z %.2f:" % z
			for yi in [0.02, 0.05, 0.08, 0.11, 0.14]:
				row += " y%.2f=%s" % [yi, "." if g.sphere_free(Vector3(-3.0, yi, z), 0.02) else "#"]
			print(row)
		print("hole ", g.hole)
		host.get_tree().quit()
		return
	if name == "upper":
		var r := g.rat
		await _wait(host, 0.5)
		var steps := [[Vector3(-1, 0, 0), "shelf", 1.38], [Vector3(0, 0, -1), "shelf", 1.78], [Vector3(0, 0, -1), "cabinet", 2.14]]
		r.teleport(Nights.world(45, 205, 93), Nights.yaw_to(Vector3.LEFT))
		await _wait(host, 0.4)
		for st in steps:
			r.rotation.y = Nights.yaw_to(st[0])
			g.cam.snap(r.rotation.y)
			if st[1] == "cabinet":  # walk to the far end of the upper shelf first
				Input.action_press("forward")
				await _wait(host, 0.55)
				Input.action_release("forward")
			await _wait(host, 0.4)
			_check("sees a jump target toward " + str(st[0]), r.has_jump_target(), "at " + str(r.global_position))
			Input.action_press("jump")
			await _wait(host, 0.05)
			Input.action_release("jump")
			for q in 13:
				await _wait(host, 0.1)
			_check("climbed onto the " + st[1], r.surface_id == st[1] and absf(r.global_position.y - st[2]) < 0.05, "surface " + r.surface_id + " y %.2f" % r.global_position.y)
		# along the cabinet tops and the shelf over the window to the fridge
		r.teleport(Nights.world(380, 15, 216), Nights.yaw_to(Vector3.RIGHT))
		g.cam.snap(r.rotation.y)
		await _wait(host, 0.3)
		Input.action_press("forward")
		await _wait(host, 5.5)
		Input.action_release("forward")
		await _wait(host, 0.5)
		_check("walked over the window shelf and the cabinets onto the fridge", r.surface_id == "fridge", "surface " + r.surface_id + " at " + str(r.global_position))
		# on the cabinet tops facing the wall: no jump onto the top of the wall (outside the room)
		r.teleport(Nights.world(200, 20, 216), Nights.yaw_to(Vector3.FORWARD))
		await _wait(host, 0.4)
		_check("no jump target onto the wall top from the cabinets", not r.has_jump_target() or r._target.y < 2.3, "target " + str(r._target))
		# outside the room: put back
		r.teleport(Vector3(0, 3.2, -3.4), 0.0)
		await _wait(host, 0.3)
		_check("brought back into the room from outside", r.global_position.y < 2.6 and r.global_position.z > -3.1, str(r.global_position))
		# push the mug off the table: it slides to the edge, falls and breaks
		var cup: Knockable = null
		for k in g.knockables:
			if k.kind == "cup": cup = k
		if cup:
			r.teleport(cup.global_position + Vector3(0, 0, 0.2), PI)
			await _wait(host, 0.3)
			g.tasks.step = maxi(g.tasks.step, 3)  # the side task shows after 3 main steps
			await _press(host, "push")
			await _wait(host, 2.5)
			_check("the mug fell off the table and broke", not cup.visible, "cup at " + str(cup.global_position) + " visible " + str(cup.visible))
			_check("side task: push the mug off the table", g.tasks.side_done.has(0))
		host.get_tree().quit()
		return
	if name == "bugs":  # regressions checked on CI
		await _bugs(host)
		host.get_tree().quit()
		return
	if name == "rules":
		await _rules(host)
		host.get_tree().quit()
		return
	if name == "physics":
		await _physics(host)
		host.get_tree().quit()
		return
	if name == "mats":
		var seen := {}
		for m in g.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			if mi.mesh == null: continue
			for i in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(i)
				var key := (mat.resource_name if mat else "none") + " | " + mat.get_class() if mat else "none"
				var par := str(mi.get_parent().name) + "/" + str(mi.name)
				if not seen.has(key): seen[key] = [0, par]
				seen[key][0] += 1
		for k in seen: print("MAT ", k, "  x", seen[k][0], "  e.g. ", seen[k][1])
		host.get_tree().quit()
		return
	if name == "stride":
		await _wait(host, 0.5)
		for a in [g.cat, g.owner_ai, g.dog]:
			if a == null: continue
			a.process_mode = Node.PROCESS_MODE_DISABLED
			_stride(a)
		host.get_tree().quit()
		return
	if name == "juice":
		await _juice(host)
		host.get_tree().quit()
		return
	if name == "mech":
		await _mech(host)
		print("DONE")
		host.get_tree().quit()
		return
	var rat := g.rat
	print("TEST ", name, " night ", g.night_id, " foods ", g.foods.size(), " zones ", g.zones.size(), " knock ", g.knockables.size())
	await _wait(host, 0.5)
	_check("rat stands on the nest floor", rat.is_on_floor(), str(rat.global_position))
	# walk out through the mouse hole: north
	Input.action_press("forward")
	await _wait(host, 1.6)
	Input.action_release("forward")
	_check("rat walked through the mouse hole", rat.global_position.z < 2.9, str(rat.global_position))
	# carry a crumb home
	rat.teleport(Nights.world(400, 500, 1), PI)
	await _wait(host, 0.3)
	var f := g.spawn_food("crumb", rat.global_position + Vector3(0, 0, -0.05), "test", false)
	await _wait(host, 0.2)
	_check("picked up a crumb", rat.carried.size() == 1, "carried %d" % rat.carried.size())
	rat.teleport(Nights.world(180, 680, 2), PI)
	await _wait(host, 0.3)
	_check("delivered it in the nest", g.fed >= 1, "fed %d" % g.fed)
	# jump onto a chair: stand west of the chair at 596,420 facing east
	rat.teleport(Nights.world(540, 420, 1), PI / 2)
	await _wait(host, 0.4)
	_check("sees a jump target at the chair", rat.has_jump_target())
	Input.action_press("jump")
	await _wait(host, 0.05)
	Input.action_release("jump")
	await _wait(host, 1.0)
	_check("jumped onto the chair", rat.surface_id == "chair", "surface " + rat.surface_id + " y %.2f" % rat.global_position.y)
	# from the chair onto the table
	rat.rotation.y = PI / 2
	await _wait(host, 0.4)
	_check("sees the table from the chair", rat.has_jump_target())
	Input.action_press("jump")
	await _wait(host, 0.05)
	Input.action_release("jump")
	await _wait(host, 1.0)
	_check("jumped onto the table", rat.surface_id == "table", "surface " + rat.surface_id + " y %.2f" % rat.global_position.y)
	# hide under the table
	rat.teleport(Nights.world(720, 445, 1), 0)
	await _wait(host, 0.4)
	_check("hidden under the table", rat.hidden(), rat.hide_kind())
	# sniff
	rat.teleport(Nights.world(400, 500, 1), 0)
	Input.action_press("sniff")
	await _wait(host, 1.0)
	Input.action_release("sniff")
	_check("sniffing raised the flag", g.tasks.flag_value("sniffed") > 0)
	# navigation
	var p := g.grid.find_path(Nights.world(300, 500), Nights.world(800, 150))
	_check("cat/owner path across the kitchen", not p.is_empty(), "%d points" % p.size())
	_check("no path into the hiding spot under the table", g.grid.blocked_at(Nights.world(720, 445)))
	print("TASK step ", g.tasks.step, " / ", g.tasks.chain.size(), "  stars ", g.stars, "  cat ", g.cat.mode, "  owner ", g.owner_ai.mode)
	print("DONE")
	host.get_tree().quit()


func _cat(host: Node) -> void:
	var rat := g.rat
	print("TEST cat night ", g.night_id, " cat mode ", g.cat.mode)
	_check("the cat is awake on night 5", g.cat.awake(), str(g.cat.mode))
	# stand in front of the cat, on the floor, in plain sight
	var c := g.cat.global_position
	var fwd := g.cat.global_transform.basis.z
	rat.teleport(c + fwd * 0.9, 0)
	await _wait(host, 3.0)
	_check("the cat spotted and chased the rat", g.run.chased or g.lives < 3, "mode %d alert %.2f lives %d" % [g.cat.mode, g.cat.alert, g.lives])
	await _wait(host, 3.0)
	_check("caught: a life lost and back at the hole", g.lives < 3, "lives %d" % g.lives)
	# hide under the table: the cat must lose her
	rat.teleport(Nights.world(720, 445, 1), 0)
	await _wait(host, 6.0)
	_check("hidden rat is not caught", not g.cat.sees, "mode %d" % g.cat.mode)
	print("DONE")
	host.get_tree().quit()


func _owner(host: Node) -> void:
	var rat := g.rat
	print("TEST owner night ", g.night_id, " plan ", g.night.get("owner", {}).get("type", ""), " at ", g.night.get("owner", {}).get("at", []))
	rat.teleport(Nights.world(720, 445, 1), 0)  # hidden under the table
	g.night_time = float(g.night.owner.at[0]) - 0.5
	await _wait(host, 5.0)
	_check("the owner came in", g.owner_ai.in_room(), "mode %d" % g.owner_ai.mode)
	_check("he switched the light on", g.room_light.visible)
	await _wait(host, 8.0)
	_check("he went to the sink for water", g.owner_ai.mode == OwnerAI.Mode.DRINK or g.owner_ai.mode == OwnerAI.Mode.PATROL, "mode %d at %s" % [g.owner_ai.mode, str(g.owner_ai.global_position)])
	_check("a hidden rat stays unseen", not g.run.seenOwner)
	g.owner_ai._t2 = 0.1
	await _wait(host, 12.0)
	_check("he left and turned the light off", g.owner_ai.mode == OwnerAI.Mode.AWAY and not g.room_light.visible, "mode %d" % g.owner_ai.mode)
	_check("task flag: the owner left", g.tasks.flag_value("ownerLeft") > 0)
	print("DONE")
	host.get_tree().quit()


## Every hiding spot must have room for the rat, and she must be able to walk in from outside it.
func _hides(host: Node) -> void:
	await _wait(host, 0.5)
	var rat := g.rat
	print("TEST hides night ", g.night_id)
	rat.frozen = true
	for z in g.zones:
		if not (z is HideSpot) or (z as HideSpot).id == "crack":
			continue
		var c: Vector3 = Vector3(z.global_position.x, 0.0, z.global_position.z)
		var low := (z as HideSpot).id == "sofa"  # under a sofa there's only room for a crouching rat
		rat._set_crouch(low)
		var room := g.box_free(c + Vector3.UP * (0.046 if low else 0.066), Vector3(0.045, 0.04 if low else 0.05, 0.045))
		# walk in: from any side that's free outside it
		var got_in := false
		if room:
			for d in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
				if got_in:
					break
				var half: float = (z.size.z if d.z != 0.0 else z.size.x) / 2.0 + 0.2
				var p: Vector3 = c + (z.global_transform.basis * d) * half
				if not g.sphere_free(p + Vector3.UP * 0.08, 0.06) or absf(p.x) > 4.7 or absf(p.z) > 2.9:
					continue
				rat.teleport(p + Vector3.UP * 0.02, 0)
				await host.get_tree().physics_frame
				for i in 80:
					var to: Vector3 = c - rat.global_position
					to.y = 0
					rat.velocity = to.normalized() * 0.9 + Vector3.DOWN * 0.5
					rat.move_and_slide()
					await host.get_tree().physics_frame
					if rat.hidden() and rat.hide_spot == z:
						got_in = true
						break
		_check("%s at %s: room %s, walked in %s" % [(z as HideSpot).id, str(c), room, got_in], room and got_in)
		rat._set_crouch(false)
	print("DONE")
	host.get_tree().quit()


## Press in the physics step, so the game's _process in the same frame sees it as just pressed (like real input).
func _press(host: Node, action: String) -> void:
	await host.get_tree().physics_frame
	Input.action_press(action)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	Input.action_release(action)


## The mechanics of whichever night is loaded.
func _mech(host: Node) -> void:
	var rat := g.rat
	var id := g.night_id
	print("TEST mech night ", id)
	await _wait(host, 0.3)
	if not (g.night.get("tunnels", []) as Array).is_empty():
		var t: Dictionary = g.night.tunnels[0]
		rat.teleport(g.cracks[int(t.a)], 0)
		await _wait(host, 0.2)
		_check("standing in a linked crack shows the prompt", g.prompt.contains("crawl"), g.prompt)
		var ok := g.use_tunnel()
		await _wait(host, 0.2)
		_check("crawled through the wall to the other crack", ok and rat.global_position.distance_to(g.cracks[int(t.b)]) < 0.2, str(rat.global_position))
		_check("task flag: tunnel", g.tasks.flag_value("tunnel") > 0)
	for z in g.zones:
		if z is StickyZone:
			rat.teleport(z.global_position + Vector3.UP * 0.02, 0)
			await _wait(host, 0.3)
			_check("stuck in the %s" % z.kind, rat.stuck_t > 0.0 and g.run.stuck, "stuck %.1f" % rat.stuck_t)
			await _wait(host, z.time + 0.5)
			_check("free again after a while", rat.stuck_t <= 0.0)
			break
	if not g.gnaws.is_empty():
		var gs: GnawSpot = g.gnaws[0]
		var n0 := g.foods.size()
		rat.teleport(gs.global_position + Vector3(0.22, 0.02, 0), 0)
		await _wait(host, 0.3)
		_check("next to the bag: gnaw prompt", gs.near(rat) and g.prompt.contains("gnaw"), g.prompt)
		for i in 160:
			gs.gnaw(1.0 / 60.0)
			await host.get_tree().process_frame
		_check("gnawed open: food spilled", gs.done and g.foods.size() > n0, "%d → %d" % [n0, g.foods.size()])
		_check("task flag: " + ("backpack" if gs.cookies else "gnaw"), g.tasks.flag_value("backpack" if gs.cookies else "gnaw") > 0)
	for z in g.noisy:
		if z.kind == "washer":
			rat.teleport(z.global_position + Vector3.UP * 0.02, 0)
			await _wait(host, 0.2)
			rat.global_position += Vector3(0.02, 0, 0)
			z._trigger(rat)
			await _wait(host, 0.3)
			_check("the washer started and hums", g.tasks.flag_value("washer") > 0 and g._wash_t > 40.0)
		if z.kind == "remote" and g.tv_light:
			z._trigger(rat)
			await _wait(host, 0.2)
			_check("the remote turned the TV on", g.tv_on and g.tv_light.visible)
	if g.dog:
		var dg := g.dog
		_check("the dog sleeps at first", dg.mode == DogAI.Mode.SLEEP)
		rat.teleport(Nights.world(500, 380, 1), 0)
		await _wait(host, 1.0)
		g.noise(dg.global_position + Vector3(0.3, 0, 0), 3.0, "Bang", true, 1.5)
		await _wait(host, 0.5)
		_check("a loud noise woke the dog", dg.mode != DogAI.Mode.SLEEP, str(dg.mode))
		dg.global_position = Nights.world(700, 540)
		dg.rotation.y = Nights.yaw_to(Vector3.LEFT)
		dg.path.clear()
		rat.teleport(Nights.world(580, 540, 1), 0)
		var lives := g.lives
		await _wait(host, 4.0)
		_check("the dog chased and caught her", g.run.dogChased and g.lives < lives, "lives %d mode %d" % [g.lives, dg.mode])
		for z in g.noisy:
			if z.kind == "puddle" or z.kind == "litter":
				dg.trail.append([rat.global_position, g.night_time])
				g.noisy_effect(z.kind, z)
				_check("the %s washed off the scent" % z.kind, dg.trail.is_empty() and g.tasks.flag_value("trailBroken") > 0)
				break
		for k in g.knockables:
			if not k.knocked:
				dg.mode = DogAI.Mode.TRACK
				g.knock_landed(k, dg.global_position + Vector3(1.0, 0, 0))
				_check("a knocked-over %s distracts the dog" % k.kind, dg.mode == DogAI.Mode.PLAY)
				break
	if g.vacuum:
		var v := g.vacuum
		if not v.on: v.start()
		var p0 := v.global_position
		await _wait(host, 3.0)
		_check("the robot vacuum is driving around", v.global_position.distance_to(p0) > 0.3, str(v.global_position))
		g.rat.teleport(v.global_position + Vector3(0.22, 0.01, 0), 0)
		var star0 := g._alarm
		await _wait(host, 0.6)
		_check("bumped into her: BEEP BEEP (alarm)", g._alarm > star0, "%.1f → %.1f" % [star0, g._alarm])
		await _wait(host, 2.6)
		Input.action_press("sneak")
		await _wait(host, 0.2)
		await host.get_tree().physics_frame
		rat.teleport(v.global_position + Vector3(0.05, 0.01, 0), 0)
		await _wait(host, 3.6)
		_check("sneaking onto it: riding the vacuum", rat.carrier == v and g.tasks.flag_value("ride") > 0, str(rat.carrier))
		Input.action_release("sneak")
		await _wait(host, 0.3)
		_check("stops sneaking: hops off", rat.carrier == null)
		v.stun()
		var p1 := v.global_position
		await _wait(host, 1.0)
		_check("stunned by a fallen thing", v.global_position.distance_to(p1) < 0.01 and g.tasks.flag_value("vacBlock") > 0)
	if not g.sleepers.is_empty():
		var z: Sleeper = g.sleepers[0]
		rat.teleport(Nights.world(300, 300, 1), 0)
		await _wait(host, 0.3)
		_check("the %s is asleep" % z.kind, z.awake_t <= 0.0 and z.sleep > 0.9)
		var a0 := g._alarm
		g.noise(z.global_position + Vector3(0.4, 0, 0.4), 3.0, "BANG", true, 1.5)
		await _wait(host, 0.3)
		_check("a loud noise woke the %s (alarm up)" % z.kind, z.awake_t > 0.0 and g.run.sleeperWoke and g._alarm > a0 + 15.0, "%.1f → %.1f" % [a0, g._alarm])
		if z.kind == "kid":
			_check("the kid's scream woke the cat", g.cat.awake() or str(g.night.get("cat", "")) == "away")
	if not g.pups.is_empty():
		var pp: Pup = g.pups[0]
		if g.vacuum: g.vacuum.on = false
		for t in g.traps: t.spring()
		for z in g.zones.duplicate():
			if z is StickyZone: g.zones.erase(z)
		g.owner_ai.mode = OwnerAI.Mode.AWAY
		g.cat.mode = CatAI.Mode.AWAY
		g.cat.visible = false
		g._alarm = 0.0
		rat.teleport(Nights.world(260, 520, 1), 0)
		for q in g.pups:
			q.mode = Pup.Mode.FOLLOW
			q.freeze_t = 0.0
			q.global_position = Nights.world(240, 540)
		rat.frozen = true
		var start := pp.global_position
		for i in 120:
			rat.global_position += Vector3(0.012, 0, -0.004)
			await host.get_tree().physics_frame
		rat.frozen = false
		await _wait(host, 1.0)
		_check("%s follows Mom" % pp.title, pp.global_position.distance_to(rat.global_position) < 0.9, "%.2f m from Mom" % pp.global_position.distance_to(rat.global_position))
		for i in 30:
			if pp.mode != Pup.Mode.CARRY and pp.mode != Pup.Mode.FETCH: break
			await _wait(host, 0.2)
		await _press(host, "pups")
		await _wait(host, 0.2)
		_check("Q: the pups wait", pp.mode == Pup.Mode.STAY and g.tasks.flag_value("pupStay") > 0, str(pp.mode))
		await _press(host, "pups")
		await _wait(host, 0.2)
		_check("Q again: they follow", pp.mode == Pup.Mode.FOLLOW)
		g.spawn_food("crumb", rat.global_position + Vector3(0.6, 0, 0.1), "", false)
		await _press(host, "fetch")
		await _wait(host, 5.0)
		_check("R: a pup fetches food and brings it home", g.tasks.flag_value("pupFetch") > 0 or pp.mode == Pup.Mode.CARRY, "mode %d fetched %d" % [pp.mode, g.tasks.flag_value("pupFetch")])
		g.cat.visible = true
		pp.capture("cat")
		_check("caught by the cat: dropped by the cat bed", pp.mode == Pup.Mode.CAPTURED and g.run.pupCaught)
		rat.teleport(pp.global_position + Vector3(0.12, 0.01, 0), 0)
		await _wait(host, 0.3)
		_check("Mom rescues the pup", not pp.lost() and g.tasks.flag_value("pupRescued") > 0, "mode %d surf %s d %.2f rat %s pup %s carrier %s" % [pp.mode, rat.surface_id, rat.global_position.distance_to(pp.global_position), str(rat.global_position), str(pp.global_position), str(rat.carrier)])
	if bool(g.night.get("storm", false)):
		g._next_bolt = 0.01
		rat.teleport(Nights.world(150, 470, 1), 0)
		await _wait(host, 1.4)
		_check("lightning then thunder: noise masked", g._storm_mask > 0.0)
		var a0 := g._alarm
		g.noise(rat.global_position, 2.0, "Thud", false)
		_check("thunder hides her noise", g._alarm == a0)
		g.night_time = float(g.night.seconds) * float(g.night.blackout) + 0.1
		await _wait(host, 0.3)
		_check("the power goes out", g._blackout and not g.room_light.visible)
	if g.exit_point != Vector3.ZERO:
		rat.teleport(g.exit_point + Vector3.UP * 0.02, 0)
		for pp in g.pups:
			pp.global_position = g.exit_point + Vector3(randf_range(-0.2, 0.2), 0, randf_range(-0.2, 0.0))
			pp.mode = Pup.Mode.STAY
			pp.target = pp.global_position
		await _wait(host, 0.3)
		_check("Mom at the exit", g.tasks.flag_value("exitMom") > 0)
		_check("the whole family is out", g.tasks.flag_value("allOut") > 0)


## A mug pushed off the table breaks on the floor; picking the same food up twice counts as evidence once.
func _bugs(host: Node) -> void:
	await _wait(host, 0.5)
	var cup: Knockable = null
	for k in g.find_children("*", "Knockable", true, false):
		if (k as Knockable).kind == "cup":
			cup = k
			break
	_check("there is a mug to knock", cup != null)
	if cup:
		var to := Vector3(0.6, 0.0, 0.4)  # push it toward the nearest edge of whatever it stands on
		var p := cup.global_position
		for d in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			if g.ray(p + Vector3.UP * 0.05 + d * 0.3, p + d * 0.3 + Vector3.DOWN * 0.2).is_empty():
				to = d
				break
		cup.knock(to * 3.0)
		await _wait(host, 3.0)
		_check("the mug fell and broke", cup._landed and not cup.visible, "landed %s at %s" % [cup._landed, str(cup.global_position)])
		_check("the broken mug no longer collides", cup.collision_layer == 0 and cup.freeze)
	var r := g.rat
	var cheese: Food = null
	for f in g.find_children("*", "Food", true, false):
		if (f as Food).is_cheese() and not (f as Food).poison:
			cheese = f
			break
	if cheese:
		r.teleport(cheese.global_position + Vector3(0.0, 0.02, -0.05), 0.0)
		await _wait(host, 0.6)
		var e1 := g._evidence
		r.drop_one()
		await _wait(host, 1.5)
		cheese.remove_meta("dropped_at") if cheese.has_meta("dropped_at") else null
		r.teleport(cheese.global_position + Vector3(0.0, 0.02, -0.05), 0.0)
		await _wait(host, 0.6)
		_check("picked the cheese up again", r.carried.has(cheese), "carrying %d" % r.carried.size())
		var others := 0.0  # anything else she happened to pick up on the way counts on its own
		for f in r.carried:
			if f != cheese and not (f as Food).poison:
				others += 9.0 if (f as Food).is_cheese() else 3.0
		_check("evidence counted once per piece", is_equal_approx(g._evidence, e1 + others) and e1 >= 9.0, "%.0f then %.0f (+%.0f other food)" % [e1, g._evidence, others])


## Free end of night 1 and the wanted level cooling down.
func _rules(host: Node) -> void:
	await _wait(host, 0.5)
	var e0: float = g._evidence
	g._evidence = 30.0
	g._quiet = 16.0
	await _wait(host, 0.3)
	var s1: int = g.stars
	g._quiet = 200.0
	g._evidence = 10.5
	await _wait(host, 2.5)
	_check("wanted level cools down when quiet", g._evidence < 10.0 and g.stars < s1 or not bool(g.night.get("wanted", false)), "stars %d -> %d ev %.1f" % [s1, g.stars, g._evidence])
	g._evidence = e0
	g.fed = int(g.night.goal)
	await _wait(host, 0.4)
	_check("full nest: the finish choice is offered", g.state == "pause" and g._goal_offered, "state " + g.state)
	g._set_paused(false)
	await _wait(host, 0.3)
	_check("keep playing", g.state == "play" and g.can_finish())
	g.finish_now()
	await _wait(host, 0.3)
	_check("finish any time", g.state == "outro", "state " + g.state)


func _physics(host: Node) -> void:
	var r := g.rat
	await _wait(host, 0.5)
	_check("the tail has its sway", r.tail != null)
	# running at the table edge: she stops and teeters instead of falling off
	r.teleport(Nights.world(700, 420, 76), Nights.yaw_to(Vector3.FORWARD))
	g.cam.snap(r.rotation.y)
	await _wait(host, 0.4)
	var saw := false
	Input.action_press("forward"); Input.action_press("run")
	for i in 90:
		await host.get_tree().physics_frame
		saw = saw or r._teeter > 0.0
	Input.action_release("forward"); Input.action_release("run")
	await _wait(host, 0.2)
	_check("running to the table edge she stops and teeters", saw and r.surface_id == "table" and r.global_position.y > 0.7, "surface %s y %.2f teeter %s" % [r.surface_id, r.global_position.y, saw])
	# turning at a run swings round in an arc
	var sp := _open_floor(1.1)
	r.teleport(sp + Vector3(0, 0.01, 0.55), Nights.yaw_to(Vector3.FORWARD))  # runs north through the clear spot
	g.cam.snap(r.rotation.y)
	await _wait(host, 0.3)
	Input.action_press("forward"); Input.action_press("run")
	await _wait(host, 0.4)
	var v0 := Vector3(r.velocity.x, 0, r.velocity.z).normalized()
	Input.action_release("forward"); Input.action_press("right")
	for i in 3:
		await host.get_tree().physics_frame
	var v1 := Vector3(r.velocity.x, 0, r.velocity.z).normalized()
	var a1 := rad_to_deg(v0.angle_to(v1))
	var a2 := 0.0  # the most she has turned within the next 0.6 s (before she may run into something)
	for i in 36:
		await host.get_tree().physics_frame
		var vv := Vector3(r.velocity.x, 0, r.velocity.z)
		if vv.length() > 0.2:
			a2 = maxf(a2, rad_to_deg(v0.angle_to(vv.normalized())))
	Input.action_release("right"); Input.action_release("run")
	_check("a run turns in an arc, not on the spot", a1 < 40.0 and a2 > 60.0, "after 3 frames %.0f°, within 0.6 s %.0f°" % [a1, a2])
	var sx: float = absf(r.tail._sx) + absf(r.tail._svx)
	_check("the tail swung in the turn", sx > 0.01, "%.3f" % sx)
	await _wait(host, 0.5)
	# a big fall dazes her
	var fp := _open_floor()
	r.teleport(fp + Vector3.UP * 1.4, 0.0)
	await _wait(host, 0.9)
	_check("a fall from 1.4 m dazes her", r.stunned() and r.global_position.y < 0.1, "stun %.2f y %.2f" % [r._stun, r.global_position.y])
	await _wait(host, 2.5)
	_check("and she gets over it", not r.stunned())
	# bumping a loose apple pushes it
	var ap: Knockable = null
	for k in g.find_children("*", "Knockable", true, false):
		if (k as Knockable).is_round():
			ap = k
			break
	if ap == null:
		print("SKIP no round thing to push on this night")
		return
	var at := _open_floor()
	ap.freeze = false
	ap.knocked = true
	ap.global_position = at + Vector3(0, 0.05, -0.2)
	await _wait(host, 0.8)
	var a0 := ap.global_position
	r.teleport(at + Vector3(0, 0.01, 0.15), Nights.yaw_to(Vector3.FORWARD))
	g.cam.snap(r.rotation.y)
	await _wait(host, 0.2)
	Input.action_press("forward")
	await _wait(host, 1.2)
	Input.action_release("forward")
	_check("bumping a loose apple nudges it", ap.global_position.distance_to(a0) > 0.05, "moved %.2f m" % ap.global_position.distance_to(a0))


## A spot on the open floor with nothing above it (for falls and pushes).
func _open_floor(room := 0.0) -> Vector3:
	for i in 600:
		var p := g.grid.random_free(1.0, g.hole_point())
		var roomy := true
		for k in 16:
			var a := k * TAU / 16.0
			for rr in [room * 0.5, room]:
				if room > 0.0 and g.grid.blocked_at(p + Vector3(cos(a), 0, sin(a)) * rr):
					roomy = false
		if not roomy:
			continue
		var clear_above := true
		for o in [Vector3.ZERO, Vector3(0.15, 0, 0), Vector3(-0.15, 0, 0), Vector3(0, 0, 0.15), Vector3(0, 0, -0.15)]:
			if not g.ray(p + o + Vector3.UP * 0.05, p + o + Vector3.UP * 1.7).is_empty():
				clear_above = false
		if clear_above and g.grid.free_point(p + Vector3(0, 0, -0.3)).distance_to(p + Vector3(0, 0, -0.3)) < 0.15 and not g.ray(p + Vector3.UP * 0.3, p + Vector3.DOWN * 0.3).is_empty():
			var h := g.ray(p + Vector3.UP * 0.3, p + Vector3.DOWN * 0.3)
			if h.position.y < 0.03:
				return h.position
	return _open_floor(room * 0.7) if room > 0.3 else Vector3.ZERO  # nothing that roomy: ask for a little less


## How fast each walk/run clip's planted feet move over the ground (m/s at speed 1): the clip must play at
## speed / this, so the feet don't slide.
func _stride(a: Node3D) -> void:
	var sk := a.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var ap := a.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var feet := []
	for b in sk.get_bone_count():
		var bn := sk.get_bone_name(b).to_lower()
		if ((bn.contains("foot") or bn.contains("toe") or bn.contains("paw")) and not bn.contains("end")) or (bn.contains("lowerleg") and bn.ends_with("_end") and not bn.begins_with("ik")):
			feet.append(b)
	if feet.is_empty():  # generic bone names (Bone.012): the four lowest leaf bones are the paws
		var leaves := []
		for b in sk.get_bone_count():
			if sk.get_bone_children(b).is_empty() and not sk.get_bone_name(b).begins_with("IK") and sk.get_bone_name(b) != "Eyes":
				leaves.append([(sk.get_bone_global_rest(b)).origin.y, b])
		leaves.sort()
		for i in mini(4, leaves.size()): feet.append(leaves[i][1])
	for clip in ["walk", "run"]:
		if not ap.has_animation(clip): continue
		ap.play(clip)
		var len := ap.get_animation(clip).length
		var n := 120
		var pos := []
		for i in n + 1:
			ap.seek(len * i / n, true)
			sk.force_update_all_bone_transforms() if sk.has_method("force_update_all_bone_transforms") else null
			var row := []
			for b in feet:
				row.append(a.global_transform.affine_inverse() * (sk.global_transform * sk.get_bone_global_pose(b)).origin)
			pos.append(row)
		var speeds := []
		for f in feet.size():
			var lo := 1e9
			for i in n + 1: lo = minf(lo, pos[i][f].y)
			var hi := -1e9
			for i in n + 1: hi = maxf(hi, pos[i][f].y)
			var tot := 0.0; var cnt := 0
			for i in n:
				if pos[i][f].y < lo + (hi - lo) * 0.2 and pos[i + 1][f].y < lo + (hi - lo) * 0.2:
					tot += absf(pos[i + 1][f].z - pos[i][f].z) / (len / n); cnt += 1
			if cnt > 0: speeds.append(tot / cnt)
		speeds.sort()
		print("STRIDE %s %s feet %d  ground speed %s  set %.2f" % [a.name, clip, feet.size(), str(speeds), a.walk_clip_speed if clip == "walk" else a.run_clip_speed])


## Game feel: forgiving jumps, quick stop, footsteps by surface, camera, danger, head turning, muffled hiding.
func _juice(host: Node) -> void:
	var r := g.rat
	await _wait(host, 0.5)
	# quick stop
	var fp := _open_floor(1.0)
	r.teleport(fp + Vector3(0, 0.01, 0.4), Nights.yaw_to(Vector3.FORWARD))
	g.cam.snap(r.rotation.y)
	await _wait(host, 0.2)
	Input.action_press("forward")
	await _wait(host, 0.6)
	Input.action_release("forward")
	var p0 := r.global_position
	await _wait(host, 0.5)
	var slide := Vector2(r.global_position.x - p0.x, r.global_position.z - p0.z).length()
	_check("letting go she stops short", slide < 0.06, "slid %.3f m" % slide)
	# coyote time: walk off the table edge and press Space a moment later
	r.teleport(fp + Vector3(0, 0.12, 0.4), 0.0)  # just stepped off a ledge: in the air, not hopping
	r._coyote = r.COYOTE
	Input.action_press("jump")
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	Input.action_release("jump")
	_check("Space just after leaving an edge still hops", r._hopping or r.velocity.y > 0.5, "vy %.2f hopping %s" % [r.velocity.y, r._hopping])
	await _wait(host, 1.2)
	# jump buffer: Space pressed in the air is remembered until landing
	r.teleport(fp + Vector3(0, 0.25, 0.4), 0.0)
	await _wait(host, 0.08)
	await _press(host, "jump")
	var hopped := false
	for i in 40:
		await host.get_tree().physics_frame
		if r._hopping and r.velocity.y > 0.3: hopped = true
	_check("Space a moment before landing hops on landing", hopped)
	await _wait(host, 1.0)
	# footsteps by surface
	_check("footsteps: floor / table / sofa / fridge", g.step_sound("floor").begins_with("step_") and g.step_sound("table") != "" and g.step_sound("sofa") == "step_soft" and g.step_sound("fridge") == "step_metal", "%s %s %s %s" % [g.step_sound("floor"), g.step_sound("table"), g.step_sound("sofa"), g.step_sound("fridge")])
	# camera shake
	g.cam.shake(0.5)
	await _wait(host, 0.05)
	_check("the camera shakes", absf(g.cam.cam.h_offset) + absf(g.cam.cam.v_offset) > 0.0005)
	await _wait(host, 1.0)
	_check("and settles", absf(g.cam.cam.h_offset) < 0.0005)
	# running widens the view
	while r.drop_one() != null:  # heavy food would slow her to a drag
		pass
	await _wait(host, 0.6)
	var fov0: float = g.cam.cam.fov
	fp = _open_floor(1.2)
	r.teleport(fp + Vector3(0, 0.01, 0.6), Nights.yaw_to(Vector3.FORWARD))
	g.cam.snap(r.rotation.y)
	Input.action_press("forward"); Input.action_press("run")
	var fov1 := fov0
	for i in 42:
		await host.get_tree().process_frame
		fov1 = maxf(fov1, g.cam.cam.fov)
	Input.action_release("forward"); Input.action_release("run")
	_check("running widens the view", fov1 > fov0 + 2.0, "%.1f -> %.1f" % [fov0, fov1])
	await _wait(host, 0.8)
	# head turns to a noise on her right
	var hp := r.global_position + r.global_transform.basis.x * 1.0 + Vector3.UP * 0.05
	r.notice(hp)
	await _wait(host, 0.6)
	var sk := r.head_look.get_skeleton()
	var hb := sk.find_bone("Head")
	var hpos := sk.global_transform * sk.get_bone_global_pose(hb).origin
	var snout := r.mouth.global_position - hpos
	snout.y = 0.0
	var fwd := r.global_transform.basis.z
	var to_n := hp - hpos
	to_n.y = 0.0
	var a_before := rad_to_deg(fwd.angle_to(to_n))
	var a_now := rad_to_deg(snout.angle_to(to_n))
	_check("she turns her head to a noise", absf(r.head_look._yaw) > 0.3 and a_now < a_before - 15.0, "yaw %.2f, snout %.0f° off the noise (body %.0f°)" % [r.head_look._yaw, a_now, a_before])
	# panting after a sprint
	r._exert = 1.0
	await _wait(host, 0.1)
	_check("panting after a sprint", r._exert > 0.9)
	# danger: chase -> slow motion, heartbeat, red edge
	if g.cat and g.cat.has_method("wake_up"):
		g.cat.visible = true
		g.cat.global_position = r.global_position + Vector3(0.8, 0, 0)
		g.cat.mode = CatAI.Mode.CHASE
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		var slowed := Engine.time_scale < 1.0
		await _wait(host, 0.6)
		_check("spotted: a moment of slow motion", slowed)
		_check("chased: the screen edge goes red", float(g.feel._mat.get_shader_parameter("amount")) > 0.1, "%.2f" % float(g.feel._mat.get_shader_parameter("amount")))
		g.cat.mode = CatAI.Mode.SLEEP
	# hiding muffles the room
	if g.feel._lp:
		for z in g.zones:
			if z is HideSpot and (z as HideSpot).id != "crack":
				r.teleport((z as Zone).global_position + Vector3(0, 0.01, 0), 0.0)
				r._sneak_toggle = true
				break
		await _wait(host, 1.2)
		_check("hiding muffles the room", not r.hidden() or g.feel._lp.cutoff_hz < 3000.0, "hidden %s cutoff %.0f" % [r.hidden(), g.feel._lp.cutoff_hz])
