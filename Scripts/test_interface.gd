extends Control
class_name Test_Interface

@onready var status_label: RichTextLabel = %StatusLabel

func _ready():
	Manager.test_interface = self

func update_status():
	var fps = Engine.get_frames_per_second()

	status_label.text = r"""FPS: %d
IK Status: %s""" % [
		fps,
		Manager.ik_status
	]