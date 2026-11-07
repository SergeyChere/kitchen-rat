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
