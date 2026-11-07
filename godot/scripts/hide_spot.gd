class_name HideSpot
extends Zone
## A hiding spot on the floor: a crack in the wall, or the space under a table, chair, sofa or shelf.
## The rat is hidden inside; the cat and the owner can't walk in. id: crack, table, chair, sofa, shelf…

var id := "crack"


func enter(rat: Rat) -> void:
	rat.hide_spot = self


func exit(rat: Rat) -> void:
	if rat.hide_spot == self:
		rat.hide_spot = null
