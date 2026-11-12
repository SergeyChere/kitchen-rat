class_name VacuumAI
extends Agent
## The robot vacuum (nights 16 and 19), ported from updateVacuum. It leaves its dock and wanders the floor (it fits
## under tables and the sofa), sucks up crumbs, and bumps into the rat: BEEP BEEP, loud enough to wake the house.
## Sneak onto it and keep sneaking to ride it. A knocked-over thing landing next to it stuns it for a while.

const R := 0.17

var on := false
var dock := Vector3.ZERO
var grid: NavGrid

var _stun := 0.0
var _bump := 0.0
var _ride := 0.0
var _led: OmniLight3D
var _wait := -1.0        # seconds of play until it wakes up by itself (-1: it waits for an event)
var _charge: OmniLight3D # the slow amber "charging" light while it sits on its dock
var _said := false


## It starts the night on its dock, charging: there to be seen (and dreaded) before it moves.
func park(delay := -1.0) -> void:
	visible = true
	global_position = dock
	_wait = delay
	_charge = OmniLight3D.new()
	_charge.light_color = Color(1.0, 0.62, 0.2)
	_charge.light_energy = 0.3
	_charge.omni_range = 0.6
	_charge.omni_attenuation = 0.6
	add_child(_charge)
	_charge.position = Vector3(0, 0.16, 0)


func start() -> void:
	if on:
		return
	on = true
	visible = true
	global_position = dock
	if _charge:
		_charge.queue_free()
		_charge = null
	path.clear()
	Sfx.play("beep", global_position)
	Sfx.loop("hum_loop", self)
	_led = OmniLight3D.new()
	_led.light_color = Color(0.4, 1.0, 0.5)
	_led.light_energy = 0.8
	_led.omni_range = 0.6
	add_child(_led)
	_led.position = Vector3(0, 0.16, 0)
	G.bubble_on("Beep boop!", self, 0.3, 1.6)


func stun() -> void:
	if not on:
		return
	_stun = 6.0
	path.clear()
	Sfx.play("beep", global_position, 0.0, 0.8)
	G.bubble_on("Error: obstacle", self, 0.3, 1.6)
	G.tasks.set_flag("vacBlock")


func _process(dt: float) -> void:
	if not on:
		if _charge:  # breathing, the way a charging light does; green for the last seconds
			var t := Time.get_ticks_msec() / 1000.0
			_charge.light_energy = 0.22 + 0.16 * sin(t * 2.2)
			if _wait >= 0.0 and _wait < 4.0:
				_charge.light_color = Color(0.4, 1.0, 0.5)
		if _wait >= 0.0 and G.playing():
			_wait -= dt
			if _wait < 4.0 and not _said:
				_said = true
				Sfx.play("beep", global_position, -6.0, 1.3)
				G.bubble_on("Charged: 100%", self, 0.3, 2.2)
			if _wait <= 0.0:
				_wait = -1.0
				start()
		return
	if not G.playing():
		return
	speed = 0.0
	_bump = maxf(0.0, _bump - dt)
	if _led:
		_led.light_color = Color(1.0, 0.4, 0.3) if _stun > 0.0 else Color(0.4, 1.0, 0.5)
		_led.visible = fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.6
	if _stun > 0.0:
		_stun -= dt
		_carry_rat()
		return
	var d := dist_rat()
	var rp := rat.global_position
	if rat.carrier == null and rat.sneaking and not rat.jumping and rp.y < 0.05 and d < R + 0.03:
		rat.carrier = self
		_ride = 0.0
		G.bubble_at("Wheee!", rp + Vector3.UP * 0.3, 1.2)
	if rat.carrier == self and (not rat.sneaking or rat.jumping):
		rat.carrier = null
	if path.is_empty():
		var t: Vector3
		if randf() < 0.4:
			t = grid.free_point(rp + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)))
		else:
			t = grid.random_free(2.0, global_position)
		path = grid.find_path(global_position, t)
	follow(0.58 + G.stars * 0.04, dt)
	_carry_rat()
	# crumbs on the floor get sucked up
	for i in range(G.foods.size() - 1, -1, -1):
		var f: Food = G.foods[i]
		if f.carried or f.is_find or f.type != "crumb" or f.global_position.y > 0.05:
			continue
		if Vector2(f.global_position.x - global_position.x, f.global_position.z - global_position.z).length() < R + 0.04:
			G.foods.remove_at(i)
			f.queue_free()
	if rat.carrier != self and _bump <= 0.0 and rat.surface_id == "floor" and not rat.jumping and rp.y < 0.05 and d < R + 0.09:
		_bump = 2.5
		var away := Vector3(rp.x - global_position.x, 0, rp.z - global_position.z).normalized()
		var to := rp + away * 0.34
		if G.sphere_free(to + Vector3.UP * 0.08, 0.05):
			rat.global_position = to
		G.noise(global_position, 6.5, "BEEP BEEP!", true)
		Sfx.play("beep", global_position, 4.0)
		path.clear()


func _carry_rat() -> void:
	if rat.carrier != self:
		return
	rat.global_position = global_position + Vector3.UP * 0.12
	_ride += get_process_delta_time()
	_bump = 1.0
	if _ride > 3.0:
		G.tasks.set_flag("ride")
		Achievements.unlock("RIDER")
