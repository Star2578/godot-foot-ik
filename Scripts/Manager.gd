extends Node


var is_baseline: bool = false
var is_simple: bool = false
var is_footik: bool = false

var ik_status: String = "Baseline (no IK)"

var test_interface: Test_Interface

func _input(event):
    if event is InputEvent:
        if Input.is_action_just_pressed("no_ik"):
            is_baseline = true
            is_simple = false
            is_footik = false
        if Input.is_action_just_pressed("simple_ik"):
            is_baseline = false
            is_simple = true
            is_footik = false
        if Input.is_action_just_pressed("foot_ik"):
            is_baseline = false
            is_simple = false
            is_footik = true

func _process(_delta):

    match true:
        is_baseline:
            ik_status = "Baseline (no IK)"
        is_simple:
            ik_status = "Simple"
        is_footik:
            ik_status = "FootIKModifier"
        _:
            ik_status = "Err"
    
    test_interface.update_status()