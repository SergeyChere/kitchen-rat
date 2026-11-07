class_name GnawSpot
extends Node3D
## A bag of grain (or the kid's backpack): hold F next to it to gnaw it open. It's noisy, then food spills out.

var cookies := false
var spawn_n := 4
var tag := ""
var model: Node3D
var progress := 0.0
var done := false
var _snd := 0.0


func near(rat: Rat) -> bool:
	if done or rat.jumping:
		return false
	var d := rat.global_position - global_position
	return absf(d.y) < 0.08 and Vector2(d.x, d.z).length() < 0.32


func gnaw(dt: float) -> void:
	if done:
		return
	var g := Game.I
	progress += dt / 2.2
	_snd -= dt
	if _snd <= 0.0:
		_snd = 0.45
		g.noise(global_position, 2.0, "Gnaw gnaw", false, 0.3)
	if progress < 1.0:
		return
	done = true
	g.tasks.set_flag("backpack" if cookies else "gnaw")
	var open := g._builder.spawn("props/backpack_open" if cookies else "props/grain_sack_open", global_position, rad_to_deg(model.rotation.y) if model else 0.0, self)
	if model:
		model.queue_free()
	model = open
	for i in spawn_n:
		var a := float(i) / spawn_n * TAU
		var p := global_position + Vector3(cos(a) * 0.26, 0.3, sin(a) * 0.26 + 0.18)
		var hit := g.ray(p, p + Vector3.DOWN * 2.0)
		var at: Vector3 = hit.position if not hit.is_empty() else Vector3(p.x, global_position.y, p.z)
		var type := "cookie" if cookies else ("cheese" if i == 0 and tag != "" else "crumb")
		g.spawn_food(type, at, tag if i == 0 else "", false)
	if not cookies:
		var z := g._builder.add_zone(NoisyZone, "Spilled grain", global_position + Vector3(0, 0, 0.22), Vector3(0.64, 0.2, 0.64)) as NoisyZone
		z.configure("grain")
		g._builder.spawn("props/grain_spill", global_position + Vector3(0, 0, 0.22), 0.0, g._builder.decor)
		g.zones.append(z)
	g.bubble_at("Cookies! The backpack is open." if cookies else "The bag is open! Careful, the grain crunches.", g.rat.global_position + Vector3.UP * 0.3, 2.4)
