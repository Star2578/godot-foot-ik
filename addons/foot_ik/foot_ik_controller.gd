@tool
extends SkeletonModifier3D

## The skeleton that this IK modifier will manipulate.
var skeleton: Skeleton3D
@export var animation: AnimationPlayer

@export_group("Raycasts")
## Raycast starting from the right heel to detect floor height.
@export var right_heel_ray: RayCast3D
## Raycast starting from the right toe to detect floor slope/angle.
@export var right_toe_ray: RayCast3D
## Raycast starting from the left heel to detect floor height.
@export var left_heel_ray: RayCast3D
## Raycast starting from the left toe to detect floor slope/angle.
@export var left_toe_ray: RayCast3D

@export_group("Bone Names")
## The name of the Hips/Pelvis bone.
@export var bone_hips := "Hips"
## The name of the right thigh (upper leg) bone.
@export var bone_right_thigh := "RightUpLeg"
## The name of the right knee (lower leg) bone.
@export var bone_right_knee := "RightLeg"
## The name of the right foot bone.
@export var bone_right_foot := "RightFoot"
## The name of the right toe bone.
@export var bone_right_toe := "RightToeBase"
## The name of the left thigh (upper leg) bone.
@export var bone_left_thigh := "LeftUpLeg"
## The name of the left knee (lower leg) bone.
@export var bone_left_knee := "LeftLeg"
## The name of the left foot bone.
@export var bone_left_foot := "LeftFoot"
## The name of the left toe bone.
@export var bone_left_toe := "LeftToeBase"

# ── Axis selection ──────────────────────────────────────────
## Defines the local axes of the skeleton bones.
enum Axis {X_POS, Y_POS, Z_POS, X_NEG, Y_NEG, Z_NEG}

@export_group("Axis Settings")
## Which LOCAL axis of the hip bone points forward.
@export var forward_axis: Axis = Axis.Z_POS
## Which LOCAL axis of the hip bone points right.
@export var right_axis: Axis = Axis.X_POS

@export_group("IK Settings")
## Small offset to keep the foot slightly above the collision point to prevent clipping.
@export var ground_snap: float = 0.015
## The maximum distance the hips are allowed to drop when crouching on uneven terrain.
@export var hip_max_drop: float = 0.55
## How quickly the hip height adjusts to new terrain (higher is faster).
@export var hip_smooth_speed: float = 8.0
## How far forward the 'virtual' pole target is placed to guide knee bending.
@export var knee_pole_forward: float = 0.6
## Adds a slight outward angle to the knees to prevent a 'knock-kneed' look.
@export var knee_outward_bias: float = 0.15
## Total length of the floor-detection raycasts.
@export var ray_length: float = 2.0
## Vertical offset above the bone where the raycast starts.
@export var ray_start_offset: float = 0.15

var idx_hips: int
var idx_r_thigh: int
var idx_r_knee: int
var idx_r_foot: int
var idx_r_toe: int
var idx_l_thigh: int
var idx_l_knee: int
var idx_l_foot: int
var idx_l_toe: int

var r_upper_len: float
var r_lower_len: float
var l_upper_len: float
var l_lower_len: float

var _hip_offset: float = 0.0
var _debug_printed := false

var min_y: float = INF
var max_y: float = - INF


func _ready():
	skeleton = get_skeleton()
	if not skeleton:
		push_error("FootIKModifier: skeleton not assigned!")
		return
	idx_hips = _req(bone_hips)
	idx_r_thigh = _req(bone_right_thigh)
	idx_r_knee = _req(bone_right_knee)
	idx_r_foot = _req(bone_right_foot)
	idx_r_toe = _req(bone_right_toe)
	idx_l_thigh = _req(bone_left_thigh)
	idx_l_knee = _req(bone_left_knee)
	idx_l_foot = _req(bone_left_foot)
	idx_l_toe = _req(bone_left_toe)
	r_upper_len = _rest_len(idx_r_thigh, idx_r_knee)
	r_lower_len = _rest_len(idx_r_knee, idx_r_foot)
	l_upper_len = _rest_len(idx_l_thigh, idx_l_knee)
	l_lower_len = _rest_len(idx_l_knee, idx_l_foot)
	print("=== FootIK segment lengths ===")
	print("  R upper: ", r_upper_len, "  lower: ", r_lower_len)
	print("  L upper: ", l_upper_len, "  lower: ", l_lower_len)


func _req(bname: String) -> int:
	var i := skeleton.find_bone(bname)
	if i < 0: push_error("FootIKModifier: bone not found: " + bname)
	return i


func _rest_len(a: int, b: int) -> float:
	return (skeleton.get_bone_global_rest(b).origin
		  - skeleton.get_bone_global_rest(a).origin).length()


func _global_pose(bone_idx: int) -> Transform3D:
	var chain: Array[int] = []
	var idx := bone_idx
	while idx >= 0:
		chain.push_front(idx)
		idx = skeleton.get_bone_parent(idx)
	var xform := Transform3D.IDENTITY
	for i in chain:
		xform = xform * skeleton.get_bone_pose(i)
	return xform


# ═══════════════════════════════════════════════════════════════
# AXIS HELPERS — enum → Vector3 → world direction via hip bone
# ═══════════════════════════════════════════════════════════════
static func _axis_vec(a: Axis) -> Vector3:
	match a:
		Axis.X_POS: return Vector3(1, 0, 0)
		Axis.Y_POS: return Vector3(0, 1, 0)
		Axis.Z_POS: return Vector3(0, 0, 1)
		Axis.X_NEG: return Vector3(-1, 0, 0)
		Axis.Y_NEG: return Vector3(0, -1, 0)
		Axis.Z_NEG: return Vector3(0, 0, -1)
	return Vector3.FORWARD


func _world_axes(skel_xform: Transform3D) -> Dictionary:
	var hip_basis := (skel_xform * _global_pose(idx_hips)).basis
	var fwd := (hip_basis * _axis_vec(forward_axis)).normalized()
	var rgt := (hip_basis * _axis_vec(right_axis)).normalized()
	# Strip vertical component from forward so knees don't tilt
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = hip_basis * _axis_vec(forward_axis)
	fwd = fwd.normalized()
	rgt.y = 0.0
	if rgt.length_squared() < 0.0001:
		rgt = hip_basis * _axis_vec(right_axis)
	rgt = rgt.normalized()
	return {"fwd": fwd, "rgt": rgt}


# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════
func _process_modification():
	if Engine.is_editor_hint():
		return
	if not skeleton:
		return
	var current_foot_y := (skeleton.get_bone_global_pose(idx_l_foot)).origin.y
	min_y = min(current_foot_y, min_y)
	max_y = max(current_foot_y, max_y)

	self.influence = smoothstep(min_y, max_y, current_foot_y)
	# self.influence = (current_foot_y - min_y) / (max_y - min_y)

	var skel_xform := skeleton.global_transform
	var axes := _world_axes(skel_xform)
	var char_fwd: Vector3 = axes["fwd"]
	var char_right: Vector3 = axes["rgt"]

	_place_ray(right_heel_ray, idx_r_foot, skel_xform)
	_place_ray(right_toe_ray, idx_r_toe, skel_xform)
	_place_ray(left_heel_ray, idx_l_foot, skel_xform)
	_place_ray(left_toe_ray, idx_l_toe, skel_xform)

	if not _debug_printed:
		_debug_printed = true
		_print_debug(skel_xform, char_fwd, char_right)

	var r_target = _foot_target(right_heel_ray, right_toe_ray,
								idx_r_foot, skel_xform, char_fwd)
	var l_target = _foot_target(left_heel_ray, left_toe_ray,
								idx_l_foot, skel_xform, char_fwd)

	_apply_hip_drop(r_target, l_target, skel_xform)
	
	if r_target != null:
		_solve_leg(idx_r_thigh, idx_r_knee, idx_r_foot,
				   r_target, true, skel_xform, char_fwd, char_right)
		_align_toe(idx_r_toe, skel_xform)

		# fallback if foot can't reach desired target
		if not _check_if_reach(idx_r_foot, r_target):
			var r_foot_pos := skeleton.to_global(skeleton.get_bone_global_pose(idx_r_foot).origin)
			
			var hit_data := _sweep_cast(r_foot_pos, 30, 0.4, 0.4)
			var hit_idx = 0
			var hit_dist = INF
			if len(hit_data) > 0:
				var hit_data_min: Dictionary
				# find hit that min distance to current foot position
				for h in hit_data:
					var curr_dist := r_foot_pos.distance_squared_to(h["position"])
					if curr_dist < hit_dist:
						hit_data_min = h
						hit_dist = curr_dist

				DebugDraw3D.draw_sphere(hit_data_min["position"], 0.01, Color.DARK_MAGENTA)

				var r_target_fallback: Vector3 = hit_data_min["position"]

				var foot_fwd: Vector3 = char_fwd
				var right_v := foot_fwd.cross(hit_data_min["normal"])
				if right_v.length_squared() < 0.0001:
					right_v = char_fwd.cross(hit_data_min["normal"])
				if right_v.length_squared() < 0.0001:
					right_v = Vector3.RIGHT
				right_v = right_v.normalized()
				foot_fwd = hit_data_min["normal"].cross(right_v).normalized()

				
				var r_target_transform := Transform3D(Basis(right_v, foot_fwd, hit_data_min["normal"]), r_target_fallback)
				_solve_leg(idx_r_thigh, idx_r_knee, idx_r_foot,
					   r_target_transform, false, skel_xform, char_fwd, char_right)

	if l_target != null:
		_solve_leg(idx_l_thigh, idx_l_knee, idx_l_foot,
				   l_target, false, skel_xform, char_fwd, char_right)
		_align_toe(idx_l_toe, skel_xform)
		
		# fallback if foot can't reach desired target
		if not _check_if_reach(idx_l_foot, l_target):
			var l_foot_pos := skeleton.to_global(skeleton.get_bone_global_pose(idx_l_foot).origin)
			
			var hit_data := _sweep_cast(l_foot_pos, 30, 0.4, 0.4)
			var hit_idx = 0
			var hit_dist = INF
			if len(hit_data) > 0:
				var hit_data_min: Dictionary
				# find hit that min distance to current foot position
				for h in hit_data:
					var curr_dist := l_foot_pos.distance_squared_to(h["position"])
					if curr_dist < hit_dist:
						hit_data_min = h
						hit_dist = curr_dist

				DebugDraw3D.draw_sphere(hit_data_min["position"], 0.01, Color.DARK_MAGENTA)

				var l_target_fallback: Vector3 = hit_data_min["position"]

				var foot_fwd: Vector3 = char_fwd
				var right_v := foot_fwd.cross(hit_data_min["normal"])
				if right_v.length_squared() < 0.0001:
					right_v = char_fwd.cross(hit_data_min["normal"])
				if right_v.length_squared() < 0.0001:
					right_v = Vector3.RIGHT
				right_v = right_v.normalized()
				foot_fwd = hit_data_min["normal"].cross(right_v).normalized()

				
				var l_target_transform := Transform3D(Basis(right_v, foot_fwd, hit_data_min["normal"]), l_target_fallback)
				_solve_leg(idx_l_thigh, idx_l_knee, idx_l_foot,
					   l_target_transform, false, skel_xform, char_fwd, char_right)
	
				
func _print_debug(skel_xform: Transform3D, fwd: Vector3, right: Vector3):
	print("=== FootIK one-shot debug ===")
	print("  skeleton pos: ", skeleton.global_position,
		  "  scale Y: ", skel_xform.basis.get_scale().y)
	var hip_basis := (skel_xform * _global_pose(idx_hips)).basis
	print("  Hip local→world  X:", hip_basis.x.normalized(),
		  "  Y:", hip_basis.y.normalized(),
		  "  Z:", hip_basis.z.normalized())
	print("  forward_axis enum:", forward_axis,
		  "  right_axis enum:", right_axis)
	print("  RESULTING forward:", fwd, "  right:", right)
	for label in ["R heel", "R toe", "L heel", "L toe"]:
		var ray: RayCast3D = null
		match label:
			"R heel": ray = right_heel_ray
			"R toe": ray = right_toe_ray
			"L heel": ray = left_heel_ray
			"L toe": ray = left_toe_ray
		if ray:
			var world_dir := ray.global_basis * ray.target_position
			print("  ", label,
				  "  pos:", ray.global_position,
				  "  dir:", world_dir.normalized(),
				  "  hit:", ray.is_colliding())
			if ray.is_colliding():
				print("    → ", ray.get_collision_point())


# ═══════════════════════════════════════════════════════════════
# RAY PLACEMENT
# ═══════════════════════════════════════════════════════════════
func _place_ray(ray: RayCast3D, bone_idx: int, skel_xform: Transform3D):
	if not ray:
		return
	var bone_world := skel_xform * _global_pose(bone_idx).origin


	ray.global_position = bone_world + Vector3(0.0, ray_start_offset, 0.0)


	var world_down := Vector3(0.0, -ray_length, 0.0)
	ray.target_position = ray.global_basis.inverse() * world_down

	ray.force_raycast_update()


# ═══════════════════════════════════════════════════════════════
# FOOT TARGET
# ═══════════════════════════════════════════════════════════════
func _foot_target(heel_ray: RayCast3D, toe_ray: RayCast3D,
				  foot_idx: int, skel_xform: Transform3D,
				  char_fwd: Vector3) -> Variant:
	if not heel_ray or not heel_ray.is_colliding():
		return null

	var heel_hit := heel_ray.get_collision_point()
	var surface_n := heel_ray.get_collision_normal()


	var foot_world_y := (skel_xform * _global_pose(foot_idx).origin).y


	if heel_hit.y > foot_world_y + 0.1:
		return null

	var foot_pos := heel_hit + surface_n * ground_snap


	var foot_fwd: Vector3
	if toe_ray and toe_ray.is_colliding():
		var raw := toe_ray.get_collision_point() - heel_hit
		foot_fwd = raw.normalized() if raw.length_squared() > 0.001 else char_fwd
	else:
		foot_fwd = char_fwd


	var right_v := foot_fwd.cross(surface_n)
	if right_v.length_squared() < 0.0001:
		right_v = char_fwd.cross(surface_n)
	if right_v.length_squared() < 0.0001:
		right_v = Vector3.RIGHT
	right_v = right_v.normalized()
	foot_fwd = surface_n.cross(right_v).normalized()

	return Transform3D(Basis(right_v, foot_fwd, surface_n), foot_pos)


# ═══════════════════════════════════════════════════════════════
# HIP DROP
# ═══════════════════════════════════════════════════════════════
func _apply_hip_drop(r_target: Variant, l_target: Variant,
					 skel_xform: Transform3D):
	var r_delta := _drop_needed(r_target, idx_r_foot, skel_xform)
	var l_delta := _drop_needed(l_target, idx_l_foot, skel_xform)


	var target_world_offset: float

	if r_target != null and l_target != null:
		# Both feet have ground contact:
		# Drop to the lower foot, but only rise to the average of both.
		# This prevents over-dropping on one-sided slopes while allowing
		# natural upward correction on raised terrain.
		var lower := minf(r_delta, l_delta) # most negative = needs most drop
		var avg := (r_delta + l_delta) * 0.5
		# If lower foot needs to drop, use that. If both need to rise, use average.
		target_world_offset = lower if lower < 0.0 else avg
	elif r_target != null:
		target_world_offset = r_delta
	elif l_target != null:
		target_world_offset = l_delta
	else:
		target_world_offset = 0.0

	# Symmetric clamp: allow equal rise and drop
	target_world_offset = clampf(target_world_offset, -hip_max_drop, hip_max_drop)

	var dt := get_process_delta_time()
	_hip_offset = lerpf(_hip_offset, target_world_offset,
						clampf(hip_smooth_speed * dt, 0.0, 1.0))

	if absf(_hip_offset) < 0.0001:
		return


	var world_offset := Vector3(0.0, _hip_offset, 0.0)


	var skel_local := skel_xform.basis.inverse() * world_offset


	var parent_idx := skeleton.get_bone_parent(idx_hips)
	if parent_idx >= 0:
		var parent_basis := _global_pose(parent_idx).basis.orthonormalized()
		skel_local = parent_basis.inverse() * skel_local

	var pose := skeleton.get_bone_pose(idx_hips)
	pose.origin += skel_local
	skeleton.set_bone_pose(idx_hips, pose)


func _drop_needed(target: Variant, foot_idx: int,
				  skel_xform: Transform3D) -> float:
	if target == null:
		return 0.0
	var foot_world_y := (skel_xform * _global_pose(foot_idx).origin).y
	return (target as Transform3D).origin.y - foot_world_y


# ═══════════════════════════════════════════════════════════════
# TWO-BONE IK
# ═══════════════════════════════════════════════════════════════
func _solve_leg(thigh_idx: int, knee_idx: int, foot_idx: int,
				target_world: Transform3D, is_right: bool,
				skel_xform: Transform3D,
				char_fwd: Vector3, char_right: Vector3):
	var skel_scale := skel_xform.basis.get_scale().y
	var upper_len := (r_upper_len if is_right else l_upper_len) * skel_scale
	var lower_len := (r_lower_len if is_right else l_lower_len) * skel_scale
	var total_len := upper_len + lower_len

	var thigh_pos := skel_xform * _global_pose(thigh_idx).origin
	var foot_pos := target_world.origin

	var to_target := foot_pos - thigh_pos
	var dist := to_target.length()
	if dist < 0.0001:
		return
	var dir := to_target / dist


	dist = clampf(dist, upper_len * 0.05, total_len * 0.98)

	# Law of cosines
	var cos_a := clampf(
		(upper_len * upper_len + dist * dist - lower_len * lower_len)
		/ (2.0 * upper_len * dist), -1.0, 1.0)
	var angle_a := acos(cos_a)

	# ── Knee pole ──


	var outward := char_right * (1.0 if is_right else -1.0) * knee_outward_bias


	var pole_dir := char_fwd + outward

	pole_dir -= dir * pole_dir.dot(dir)
	if pole_dir.length_squared() < 0.0001:
		pole_dir = Vector3.UP
		pole_dir -= dir * pole_dir.dot(dir)
	if pole_dir.length_squared() < 0.0001:
		pole_dir = Vector3.RIGHT

	pole_dir = pole_dir.normalized()


	var pole_dist := upper_len * knee_pole_forward
	var pole_pos := (thigh_pos + foot_pos) * 0.5 + pole_dir * pole_dist


	var to_pole := pole_pos - thigh_pos
	var plane_n := dir.cross(to_pole)
	if plane_n.length_squared() < 0.0001:
		plane_n = dir.cross(
			Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT)
	plane_n = plane_n.normalized()


	var desired_knee_pos := thigh_pos + dir.rotated(plane_n, angle_a) * upper_len

	# Apply rotations
	var knee_cur_pos := skel_xform * _global_pose(knee_idx).origin
	_rotate_bone_toward(thigh_idx, thigh_pos,
						knee_cur_pos, desired_knee_pos, skel_xform)

	var knee_new_pos := skel_xform * _global_pose(knee_idx).origin
	var foot_cur_pos := skel_xform * _global_pose(foot_idx).origin
	_rotate_bone_toward(knee_idx, knee_new_pos,
						foot_cur_pos, foot_pos, skel_xform)

	# if foot_idx == idx_l_foot:
		# DebugDraw3D.draw_gizmo(target_world,Color.BLACK)
		# DebugDraw3D.draw_gizmo(skeleton.global_transform*skeleton.get_bone_global_pose(idx_l_foot))
		# DebugDraw3D.draw_gizmo(skeleton.global_transform * skeleton.get_bone_rest(idx_l_foot))
	_rotate_foot_to_surface(foot_idx, target_world.basis, skel_xform)


# ═══════════════════════════════════════════════════════════════
# TOE BONE RESET
# ═══════════════════════════════════════════════════════════════
func _align_toe(toe_idx: int, skel_xform: Transform3D):
	var pose := skeleton.get_bone_pose(toe_idx)
	var original_scale := pose.basis.get_scale()
	pose.basis = Basis.IDENTITY.scaled(original_scale)
	skeleton.set_bone_pose(toe_idx, pose)


# ═══════════════════════════════════════════════════════════════
# BONE ROTATION HELPER
# ═══════════════════════════════════════════════════════════════
func _rotate_bone_toward(bone_idx: int,
						 bone_world: Vector3,
						 child_cur: Vector3, child_des: Vector3,
						 skel_xform: Transform3D):
	var from_dir := (child_cur - bone_world).normalized()
	var to_dir := (child_des - bone_world).normalized()
	if from_dir.dot(to_dir) > 0.9999:
		return

	var world_axis := from_dir.cross(to_dir)
	if world_axis.length_squared() < 0.0001:
		return
	world_axis = world_axis.normalized()
	var angle := from_dir.angle_to(to_dir)


	var parent_idx := skeleton.get_bone_parent(bone_idx)
	var parent_basis: Basis
	if parent_idx >= 0:
		parent_basis = (skel_xform * _global_pose(parent_idx)).basis.orthonormalized()
	else:
		parent_basis = skel_xform.basis.orthonormalized()

	var local_axis := parent_basis.inverse() * world_axis

	var pose := skeleton.get_bone_pose(bone_idx)
	var original_scale := pose.basis.get_scale()
	pose.basis = Basis(local_axis.normalized(), angle) * pose.basis
	pose.basis = pose.basis.orthonormalized().scaled(original_scale)
	skeleton.set_bone_pose(bone_idx, pose)


# ═══════════════════════════════════════════════════════════════
# FOOT SURFACE ALIGNMENT
# ═══════════════════════════════════════════════════════════════


func _rotate_foot_to_surface(foot_idx: int, target_world_basis: Basis,
							 skel_xform: Transform3D):
	var parent_idx := skeleton.get_bone_parent(foot_idx)


	var parent_world_xform: Transform3D
	if parent_idx >= 0:
		parent_world_xform = skel_xform * _global_pose(parent_idx)
	else:
		parent_world_xform = skel_xform


	var local_basis := parent_world_xform.basis.inverse() \
					   * target_world_basis.orthonormalized()

	var pose := skeleton.get_bone_pose(foot_idx)
	var original_scale := pose.basis.get_scale()


	pose.basis = local_basis.orthonormalized().scaled(original_scale)
	skeleton.set_bone_pose(foot_idx, pose)


# ═══════════════════════════════════════════════════════════════
# DEBUG DRAW
# ═══════════════════════════════════════════════════════════════
func _debug_draw(skel_xform: Transform3D, fwd: Vector3, right: Vector3):
	for pair in [[idx_r_thigh, idx_r_knee], [idx_r_knee, idx_r_foot],
				 [idx_l_thigh, idx_l_knee], [idx_l_knee, idx_l_foot]]:
		var a := skel_xform * _global_pose(pair[0]).origin
		var b := skel_xform * _global_pose(pair[1]).origin
		# DebugDraw3D.draw_line(a, b, Color.YELLOW)


	for ray in [right_heel_ray, right_toe_ray, left_heel_ray, left_toe_ray]:
		if not ray:
			continue
		var world_end = ray.global_position + ray.global_basis * ray.target_position
		DebugDraw3D.draw_line(ray.global_position, world_end, Color.GREEN)

		DebugDraw3D.draw_sphere(ray.global_position, 0.02, Color.CYAN)
		if ray.is_colliding():
			DebugDraw3D.draw_sphere(ray.get_collision_point(), 0.03, Color.RED)

	# Forward = green, Right = red, Up = blue
	# var hp := (skel_xform * _global_pose(idx_hips)).origin
	# DebugDraw3D.draw_line(hp, hp + fwd * 0.4, Color.GREEN)
	# DebugDraw3D.draw_line(hp, hp + right * 0.3, Color.RED)
	# DebugDraw3D.draw_line(hp, hp + Vector3.UP * 0.3, Color.BLUE)


func _check_if_reach(bone_idx: int, ray_target: Transform3D) -> bool:
	var local_bone_pose := skeleton.get_bone_global_pose(bone_idx)
	var global_bone_pos := skeleton.to_global(local_bone_pose.origin)

	if global_bone_pos.distance_squared_to(ray_target.origin) > 0.000001:
		return false
		
	return true


func _sweep_cast(center: Vector3, step_degrees: float,
					  ray_length: float, angle_threshold: float, collision_mask: int = 1) -> Array[Dictionary]:
	"""
	angle_threshold - discard hit that less than this value ( 1.0 = flat, 0.0 = vertical wall, -1.0 = ceiling )
	"""
	var results: Array[Dictionary] = []
	var space := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.new()
	params.collision_mask = collision_mask

	var angle := 0.0
	while angle < 360.0:
		var rad := deg_to_rad(angle)
		var offset := Vector3(cos(rad), 0.0, sin(rad))
		var ray_from := center
		var dir := Basis.from_euler(Vector3(0, rad, 0)).x
		var ray_to := ray_from + (dir * ray_length)


		# DebugDraw3D.draw_arrow_ray(ray_from, dir, ray_length, Color.ALICE_BLUE, 0.05)

		params.from = ray_from
		params.to = ray_to

		var hit := space.intersect_ray(params)


		if hit:
			var steepness: float = hit["normal"].dot(Vector3.UP)
			if steepness > angle_threshold:
				results.append({
					"hit": true,
					"angle": angle,
					"position": hit["position"],
					"normal": hit["normal"],
					"offset": offset
				})

		angle += step_degrees

	return results
