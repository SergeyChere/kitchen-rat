class_name HumZone
extends Zone
## A humming fridge or washer: inside it the rat's quiet footsteps can't be heard.


func enter(_rat: Rat) -> void:
	Game.I.in_hum += 1


func exit(_rat: Rat) -> void:
	Game.I.in_hum = maxi(0, Game.I.in_hum - 1)
