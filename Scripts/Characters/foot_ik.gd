extends Node3D
class_name FootIK

@export var skeleton: Skeleton3D
@export var player_mesh : Node3D

@export_group("right")
@export var right_target_node: Node3D
@export var right_pole_node: Node3D
@export var right_heel_raycast_3d: RayCast3D
@export var right_toe_raycast_3d: RayCast3D
@export_group("left")
@export var left_target_node: Node3D
@export var left_pole_node: Node3D
@export var left_heel_raycast_3d: RayCast3D
@export var left_toe_raycast_3d: RayCast3D

var hips_idx: int
var right_foot_idx: int
var right_toe_idx: int
var right_knee_idx: int
var left_foot_idx: int
var left_toe_idx: int
var left_knee_idx: int

var skeleton_base_y: float

func _ready():
	skeleton_base_y = skeleton.position.y
	hips_idx = skeleton.find_bone("Hips")
	right_foot_idx = skeleton.find_bone("RightFoot")
	right_toe_idx = skeleton.find_bone("RightToeBase")
	right_knee_idx = skeleton.find_bone("RightLeg")
	left_foot_idx = skeleton.find_bone("LeftFoot")
	left_toe_idx = skeleton.find_bone("LeftToeBase")
	left_knee_idx = skeleton.find_bone("LeftLeg")

func _process(delta):
	var right_offset = get_foot_offset(right_foot_idx, right_heel_raycast_3d)
	var left_offset = get_foot_offset(left_foot_idx, left_heel_raycast_3d)
	apply_hip_offset(min(right_offset, left_offset))
	
	solver(right_foot_idx, right_toe_idx, right_knee_idx, right_heel_raycast_3d, right_toe_raycast_3d, right_pole_node, right_target_node)
	solver(left_foot_idx, left_toe_idx, left_knee_idx, left_heel_raycast_3d, left_toe_raycast_3d, left_pole_node, left_target_node)
	draw_gizmos()

func solver(foot_bone_idx: int, toe_bone_idx: int, knee_bone_idx: int, heel_raycast: RayCast3D, toe_raycast: RayCast3D, pole_node: Node3D, target_node: Node3D):
	var f_bone_local = skeleton.get_bone_global_pose(foot_bone_idx)
	var f_bone_world = skeleton.global_transform * f_bone_local
	heel_raycast.global_position = f_bone_world.origin

	var t_bone_local = skeleton.get_bone_global_pose(toe_bone_idx)
	var t_bone_world = skeleton.global_transform * t_bone_local
	toe_raycast.global_position = t_bone_world.origin

	var k_bone_world = skeleton.global_transform * skeleton.get_bone_global_pose(knee_bone_idx)
	pole_node.global_position = k_bone_world.origin + player_mesh.global_basis.z * 0.5
	
	if heel_raycast.is_colliding() and toe_raycast.is_colliding():
		var heel_hit = heel_raycast.get_collision_point()
		var toe_hit = toe_raycast.get_collision_point()

		DebugDraw3D.draw_sphere(heel_hit, 0.05, Color.YELLOW)
		DebugDraw3D.draw_sphere(f_bone_world.origin, 0.05, Color.WHITE)
	
		# surface normal from heel
		var ground_normal = heel_raycast.get_collision_normal()
	
		# forward direction = from heel to toe
		var forward = (toe_hit - heel_hit).normalized()
	
		# recalculate right axis to be perpendicular to both
		var right = forward.cross(ground_normal).normalized()
	
		# rebuild forward to be clean
		forward = ground_normal.cross(right).normalized()
	
		target_node.global_basis = Basis(right, ground_normal, -forward)
		target_node.global_position = heel_hit

func get_foot_offset(foot_bone_idx: int, heel_raycast: RayCast3D) -> float:
	if not heel_raycast.is_colliding():
		return 0.0
	var f_bone_world = skeleton.global_transform * skeleton.get_bone_global_pose(foot_bone_idx)
	return heel_raycast.get_collision_point().y - f_bone_world.origin.y

func apply_hip_offset(offset: float):
	print("offset: ", offset, " skeleton.y: ", skeleton.position.y)
	var target_y = skeleton_base_y  + offset
	skeleton.position.y = lerpf(skeleton.position.y, target_y, 0.1)

func draw_gizmos():
	# for easier debugging during play test in godot
	DebugDraw3D.draw_sphere(right_target_node.global_position, 0.03, Color.BLUE)
	DebugDraw3D.draw_sphere(left_target_node.global_position, 0.03, Color.RED)

	DebugDraw3D.draw_sphere(right_pole_node.global_position, 0.03, Color.DEEP_SKY_BLUE)
	DebugDraw3D.draw_sphere(left_pole_node.global_position, 0.03, Color.DEEP_PINK)

	DebugDraw3D.draw_ray(right_heel_raycast_3d.global_position, Vector3.DOWN, -right_heel_raycast_3d.target_position.y, Color.GREEN)
	DebugDraw3D.draw_ray(right_toe_raycast_3d.global_position, Vector3.DOWN, -right_toe_raycast_3d.target_position.y, Color.GREEN)

	DebugDraw3D.draw_ray(left_heel_raycast_3d.global_position, Vector3.DOWN, -left_heel_raycast_3d.target_position.y, Color.ORANGE)
	DebugDraw3D.draw_ray(left_toe_raycast_3d.global_position, Vector3.DOWN, -left_toe_raycast_3d.target_position.y, Color.ORANGE)
