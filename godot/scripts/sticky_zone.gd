class_name StickyZone
extends Zone
## Sticky tape, a cage trap or a cloud of poison spray (the prototype's L.sticky): step in and you're stuck for a while,
## squeaking. Pups that walk into tape or a cage get stuck too.

var kind := "sticky"
var time := 2.2
var label := "Ugh, sticky tape!"


func on_floor() -> bool:
	return global_position.y < 0.05
