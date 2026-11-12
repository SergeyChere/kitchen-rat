class_name CatEyes
extends SkeletonModifier3D
## The cat's eyes hang on one bone ("Eyes") that every clip animates, so closing them has to happen after the
## animation: this shrinks that bone to nothing while `shut` is set, and her face is plain fur where they were.

var shut := false
var _bone := -1


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _bone < 0:
		_bone = sk.find_bone("Eyes")
		if _bone < 0:
			return
	if shut:
		sk.set_bone_pose_scale(_bone, Vector3.ONE * 0.02)
