class_name NestZone
extends Zone
## The nest behind the mouse hole. Food carried in here is delivered.


func enter(rat: Rat) -> void:
	rat.in_nest = true


func exit(rat: Rat) -> void:
	rat.in_nest = false


func stay(rat: Rat, _dt: float) -> void:
	if not rat.carried.is_empty() and not rat.jumping and Game.I.playing():
		Game.I.deliver()
