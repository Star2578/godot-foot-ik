@tool
extends Node3D

@export_group("Left")
@export var l_bone_ik: TwoBoneIK3D
@export var l_root_bone: String
@export var l_middle_bone: String
@export var l_end_bone: String
@export var l_toe_bone: String


@export_group("Right")
@export var r_bone_ik: TwoBoneIK3D
@export var r_root_bone: String
@export var r_middle_bone: String
@export var r_end_bone: String
@export var r_toe_bone: String

@onready var l_heel_raycast: RayCast3D = $L_Affector/HeelRayCast3D
@onready var l_heel_target: Marker3D = $L_Affector/HeelMarker
@onready var l_toe_raycast: RayCast3D = $L_Affector/ToeRayCast3D
@onready var l_toe_target: Marker3D = $L_Affector/ToeMarker

@onready var r_heel_raycast: RayCast3D = $R_Affector/HeelRayCast3D
@onready var r_heel_target: Marker3D = $R_Affector/HeelMarker
@onready var r_toe_raycast: RayCast3D = $R_Affector/ToeRayCast3D
@onready var r_toe_target: Marker3D = $R_Affector/ToeMarker

@export_group("Animation Blend")
@export var animation_player:AnimationPlayer
@export var blend_speed: float = 100.0

@export_group("Parameters")
@export_range(0.0,1.0,0.01) var ik_influence:float = 0.6
## Offset of the heel target from ground
@export var heel_offset:float = 0.0

var skeleton: Skeleton3D

var l_root_bone_idx: int
var l_middle_bone_idx: int
var l_end_bone_idx: int
var l_toe_bone_idx: int

var r_root_bone_idx: int
var r_middle_bone_idx: int
var r_end_bone_idx: int
var r_toe_bone_idx: int

@export var l_foot_max_height: float = 0.25
@export var r_foot_max_height: float = 0.25

# @export var player_mesh : Node3D

# @export_group("other")
# @export var animation_tree : AnimationTree
# @export var active_at_ground: bool = true

# var hips_idx: int

# var skeleton_base_y: float

# var left_ik_weight:float = 0.0
# var right_ik_weight:float = 0.0
# var foot_lift_height :float = 0.3

func _validate_property(property: Dictionary) -> void:
	if property.type == TYPE_STRING and property.name.ends_with("_bone"):
		if skeleton:
			property.hint = PROPERTY_HINT_ENUM
			property.hint_string = skeleton.get_concatenated_bone_names()

func _get_configuration_warnings():
	var warnings = []

	if (skeleton == null) or not (skeleton is Skeleton3D):
		warnings.append("Missing parent, please place the node inside Skeleton3D node")

	return warnings

func _enter_tree():
	# Find parent Skeleton3D
	var parent_node = get_parent()
	assert((parent_node != null) and (parent_node is Skeleton3D) , "Parent is not a Skeleton3D")
	skeleton = parent_node
	print("Detected parent Skeleton3D: ", skeleton.name)

	notify_property_list_changed()

func _ready():
	l_root_bone_idx = skeleton.find_bone(l_root_bone)
	l_middle_bone_idx = skeleton.find_bone(l_middle_bone)
	l_end_bone_idx = skeleton.find_bone(l_end_bone)
	l_toe_bone_idx = skeleton.find_bone(l_toe_bone)

	r_root_bone_idx = skeleton.find_bone(r_root_bone)
	r_middle_bone_idx = skeleton.find_bone(r_middle_bone)
	r_end_bone_idx = skeleton.find_bone(r_end_bone)
	r_toe_bone_idx = skeleton.find_bone(r_toe_bone)
	assign_bone_ik_param()

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	update_raycast()
	# update_ik_influence(delta)
	update_affector()

	# Called after IK is solved
	update_feet_rotation()
	draw_gizmos()


func assign_bone_ik_param():
	"""
	Set corresponding value to both TwoBoneIK3D (left/right)
	"""
	l_bone_ik.set_target_node(0,l_heel_target.get_path())
	l_bone_ik.set_root_bone(0,l_root_bone_idx)
	l_bone_ik.set_middle_bone(0,l_middle_bone_idx)
	l_bone_ik.set_end_bone(0,l_end_bone_idx)
	l_bone_ik.influence = ik_influence

	r_bone_ik.set_target_node(0,r_heel_target.get_path())
	r_bone_ik.set_root_bone(0,r_root_bone_idx)
	r_bone_ik.set_middle_bone(0,r_middle_bone_idx)
	r_bone_ik.set_end_bone(0,r_end_bone_idx)
	r_bone_ik.influence = ik_influence

func update_ik_influence(delta:float):
	var l_end_bone_y = get_foot_anim_height(l_end_bone_idx)
	var r_end_bone_y = get_foot_anim_height(l_end_bone_idx)

	# How high is the animated foot above ground
	var l_height = l_end_bone_y - l_heel_raycast.get_collision_point().y
	var r_height = r_end_bone_y - r_heel_raycast.get_collision_point().y

	var l_target = 1.0 - clampf(l_height / l_foot_max_height, 0.0, 1.0)
	var r_target = 1.0 - clampf(r_height / r_foot_max_height, 0.0, 1.0)

	l_bone_ik.influence = move_toward(l_bone_ik.influence, l_target, delta * blend_speed)
	r_bone_ik.influence = move_toward(r_bone_ik.influence, r_target, delta * blend_speed)

func update_raycast():
	"""
	update raycast position to follow skeleton's heel bone
	"""
	var l_end_bone_local = skeleton.get_bone_global_pose(l_end_bone_idx)
	var l_end_bone_world = skeleton.global_transform * l_end_bone_local
	l_heel_raycast.global_position = l_end_bone_world.origin + (Vector3.UP * 0.4)

	var r_end_bone_local = skeleton.get_bone_global_pose(r_end_bone_idx)
	var r_end_bone_world = skeleton.global_transform * r_end_bone_local
	r_heel_raycast.global_position = r_end_bone_world.origin + (Vector3.UP * 0.4)


	var l_toe_bone_local = skeleton.get_bone_global_pose(l_toe_bone_idx)
	var l_toe_bone_world = skeleton.global_transform * l_toe_bone_local
	l_toe_raycast.global_position = l_toe_bone_world.origin + (Vector3.UP * 0.4)

	var r_toe_bone_local = skeleton.get_bone_global_pose(r_toe_bone_idx)
	var r_toe_bone_world = skeleton.global_transform * r_toe_bone_local
	r_toe_raycast.global_position = r_toe_bone_world.origin + (Vector3.UP * 0.4)

func update_affector():
	"""
	update affector to ground below feet
	"""
	var heel_offset_vec = Vector3.UP * heel_offset

	if l_heel_raycast.is_colliding():
		var l_heel_hit = l_heel_raycast.get_collision_point()
		l_heel_target.global_position = l_heel_hit + heel_offset_vec

	if r_heel_raycast.is_colliding():
		var r_heel_hit = r_heel_raycast.get_collision_point()
		r_heel_target.global_position = r_heel_hit + heel_offset_vec

func get_foot_anim_height(bone_idx: int) -> float:
	# This is the bone position from animation, before IK
	var bone_pose = skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)
	return bone_pose.origin.y

func draw_gizmos():
	# for easier debugging during play test in godot
	DebugDraw3D.draw_sphere(l_heel_target.global_position, 0.03, Color.BLUE)
	DebugDraw3D.draw_sphere(r_heel_target.global_position, 0.03, Color.RED)

	# DebugDraw3D.draw_sphere(right_pole_node.global_position, 0.03, Color.DEEP_SKY_BLUE)
	# DebugDraw3D.draw_sphere(left_pole_node.global_position, 0.03, Color.DEEP_PINK)

	DebugDraw3D.draw_ray(l_heel_raycast.global_position, Vector3.DOWN, -l_heel_raycast.target_position.y, Color.ORANGE)
	DebugDraw3D.draw_ray(l_toe_raycast.global_position, Vector3.DOWN, -l_toe_raycast.target_position.y, Color.GREEN)

	DebugDraw3D.draw_ray(r_heel_raycast.global_position, Vector3.DOWN, -r_heel_raycast.target_position.y, Color.ORANGE)
	DebugDraw3D.draw_ray(r_toe_raycast.global_position, Vector3.DOWN, -r_toe_raycast.target_position.y, Color.GREEN)
# 	skeleton_base_y = skeleton.position.y
# 	hips_idx = skeleton.find_bone("Hips")
