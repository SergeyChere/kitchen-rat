class_name Zone
extends Node3D
## A box-shaped area (local space, centred on the node, bottom at y = 0). The game checks the rat against it every frame.

var size := Vector3(0.4, 0.3, 0.4)
var inside := false


func contains(p: Vector3) -> bool:
	var l := to_local(p)
	return absf(l.x) <= size.x * 0.5 and absf(l.z) <= size.z * 0.5 and l.y >= -0.05 and l.y <= size.y


## Is the point inside the footprint, grown by margin (height ignored)?
func contains_xz(p: Vector3, margin: float) -> bool:
	var l := to_local(p)
	return absf(l.x) <= size.x * 0.5 + margin and absf(l.z) <= size.z * 0.5 + margin


func enter(_rat: Rat) -> void:
	pass


func stay(_rat: Rat, _dt: float) -> void:
	pass


func exit(_rat: Rat) -> void:
	pass
