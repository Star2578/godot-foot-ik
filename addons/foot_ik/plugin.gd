@tool
extends EditorPlugin

func _enter_tree() -> void:
	add_custom_type(
		"FootIKController",
		"SkeletonModifier3D",
		preload("foot_ik_controller.gd"),
		preload("icon.svg")
	)

func _exit_tree() -> void:
	remove_custom_type("FootIKController")
