extends Node


var is_baseline: bool = true
var is_simple: bool = false
var is_footik: bool = false

var ik_status: String = "Baseline (no IK)"

var test_interface: Test_Interface
var player: CharacterBody3D
var player_simple: CharacterBody3D


func _input(event):
	if event is InputEvent:
		if Input.is_action_just_pressed("no_ik"):
			is_baseline = true
			is_simple = false
			is_footik = false
			toggle_ik(is_baseline, is_simple, is_footik)
		if Input.is_action_just_pressed("simple_ik"):
			is_baseline = false
			is_simple = true
			is_footik = false
			toggle_ik(is_baseline, is_simple, is_footik)
		if Input.is_action_just_pressed("foot_ik"):
			is_baseline = false
			is_simple = false
			is_footik = true
			toggle_ik(is_baseline, is_simple, is_footik)

func _process(_delta):
	if test_interface:
		test_interface.update_status()

func toggle_ik(baseline: bool, simple: bool, footik: bool):
	match true:
		is_baseline:
			ik_status = "Baseline (no IK)"
		is_simple:
			ik_status = "Simple"
		is_footik:
			ik_status = "FootIKModifier"
		_:
			ik_status = "Err"
	if simple and player_simple and player:
		player_simple.show()
		player_simple.l_twobone_ik.active = true
		player_simple.r_twobone_ik.active = true
		player.hide()
		player.foot_ik_controller.active = false
	elif footik:
		player_simple.l_twobone_ik.active = false
		player_simple.r_twobone_ik.active = false
		player_simple.hide()
		player.foot_ik_controller.active = true
		player.show()
	elif baseline:
		player_simple.hide()
		player_simple.l_twobone_ik.active = false
		player_simple.r_twobone_ik.active = false
		player.show()
		player.foot_ik_controller.active = false
