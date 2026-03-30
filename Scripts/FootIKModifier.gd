extends SkeletonModifier3D
class_name FootIKModifier

@export var player_mesh: Node3D
@export var skeleton: Skeleton3D

@export var right_heel_ray: RayCast3D
@export var right_toe_ray:  RayCast3D
@export var left_heel_ray:  RayCast3D
@export var left_toe_ray:   RayCast3D

@export var bone_hips        := "Hips"
@export var bone_right_thigh := "RightUpLeg"
@export var bone_right_knee  := "RightLeg"
@export var bone_right_foot  := "RightFoot"
@export var bone_right_toe   := "RightToeBase"
@export var bone_left_thigh  := "LeftUpLeg"
@export var bone_left_knee   := "LeftLeg"
@export var bone_left_foot   := "LeftFoot"
@export var bone_left_toe    := "LeftToeBase"

@export var ground_snap       : float = 0.015   # sole hover above hit point
@export var hip_max_drop      : float = 0.55    # max hip sink in world meters
@export var hip_smooth_speed  : float = 8.0     # hip lerp speed
@export var knee_pole_forward : float = 0.5     # pole distance (× upper_len)
@export var knee_outward_bias : float = 0.15    # slight outward knee spread
@export var ray_length        : float = 2.0     # how far rays cast down
@export var ray_start_offset  : float = 0.15    # ★ rays start THIS far above bone

var idx_hips    : int
var idx_r_thigh : int
var idx_r_knee  : int
var idx_r_foot  : int
var idx_r_toe   : int
var idx_l_thigh : int
var idx_l_knee  : int
var idx_l_foot  : int
var idx_l_toe   : int

var r_upper_len : float
var r_lower_len : float
var l_upper_len : float
var l_lower_len : float

var _hip_offset : float = 0.0
var _debug_printed := false


func _ready():
	if not skeleton:
		push_error("FootIKModifier: skeleton not assigned!")
		return
	idx_hips    = _req(bone_hips)
	idx_r_thigh = _req(bone_right_thigh)
	idx_r_knee  = _req(bone_right_knee)
	idx_r_foot  = _req(bone_right_foot)
	idx_r_toe   = _req(bone_right_toe)
	idx_l_thigh = _req(bone_left_thigh)
	idx_l_knee  = _req(bone_left_knee)
	idx_l_foot  = _req(bone_left_foot)
	idx_l_toe   = _req(bone_left_toe)
	r_upper_len = _rest_len(idx_r_thigh, idx_r_knee)
	r_lower_len = _rest_len(idx_r_knee,  idx_r_foot)
	l_upper_len = _rest_len(idx_l_thigh, idx_l_knee)
	l_lower_len = _rest_len(idx_l_knee,  idx_l_foot)
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


# ═══════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════
func _process_modification():
	if not skeleton:
		return

	var skel_xform := skeleton.global_transform

	_place_ray(right_heel_ray, idx_r_foot, skel_xform)
	_place_ray(right_toe_ray,  idx_r_toe,  skel_xform)
	_place_ray(left_heel_ray,  idx_l_foot, skel_xform)
	_place_ray(left_toe_ray,   idx_l_toe,  skel_xform)

	if not _debug_printed:
		_debug_printed = true
		_print_debug(skel_xform)

	var r_target = _foot_target(right_heel_ray, right_toe_ray, idx_r_foot, skel_xform)
	var l_target = _foot_target(left_heel_ray,  left_toe_ray,  idx_l_foot, skel_xform)

	_apply_hip_drop(r_target, l_target, skel_xform)

	if r_target != null:
		_solve_leg(idx_r_thigh, idx_r_knee, idx_r_foot,
				   r_target, true, skel_xform)
	if l_target != null:
		_solve_leg(idx_l_thigh, idx_l_knee, idx_l_foot,
				   l_target, false, skel_xform)

	_debug_draw(skel_xform)


func _print_debug(skel_xform: Transform3D):
	print("=== FootIK one-shot debug ===")
	print("  skeleton pos: ", skeleton.global_position,
		  "  scale Y: ", skel_xform.basis.get_scale().y)
	var hip_basis := (skel_xform * _global_pose(idx_hips)).basis
	print("  Hip world axes  X(right):", hip_basis.x.normalized(),
		  "  Y(fwd):", hip_basis.y.normalized(),
		  "  Z(up):", hip_basis.z.normalized())
	for label in ["R heel", "R toe", "L heel", "L toe"]:
		var ray: RayCast3D = null
		match label:
			"R heel": ray = right_heel_ray
			"R toe":  ray = right_toe_ray
			"L heel": ray = left_heel_ray
			"L toe":  ray = left_toe_ray
		if ray:
			var world_dir := ray.global_basis * ray.target_position
			print("  ", label,
				  "  pos:", ray.global_position,
				  "  world_dir:", world_dir.normalized(),
				  "  hit:", ray.is_colliding())
			if ray.is_colliding():
				print("    → ", ray.get_collision_point())


# ═══════════════════════════════════════════════════════════
# RAY PLACEMENT — start ABOVE foot bone to prevent clipping
# ═══════════════════════════════════════════════════════════
func _place_ray(ray: RayCast3D, bone_idx: int, skel_xform: Transform3D):
	if not ray:
		return
	var bone_world := skel_xform * _global_pose(bone_idx).origin

	# ★ Start ray above the foot bone so it never sits inside geometry
	ray.global_position = bone_world + Vector3(0.0, ray_start_offset, 0.0)

	# Force the ray to aim straight down in WORLD space,
	# regardless of how the external Node3D parent is rotated
	var world_down := Vector3(0.0, -ray_length, 0.0)
	ray.target_position = ray.global_basis.inverse() * world_down

	ray.force_raycast_update()


# ═══════════════════════════════════════════════════════════
# FOOT TARGET — build a Transform3D at the ground contact
# ═══════════════════════════════════════════════════════════
func _foot_target(heel_ray: RayCast3D, toe_ray: RayCast3D,
				  foot_idx: int, skel_xform: Transform3D) -> Variant:
	if not heel_ray or not heel_ray.is_colliding():
		return null

	var heel_hit  := heel_ray.get_collision_point()
	var surface_n := heel_ray.get_collision_normal()

	# Compare hit Y against the actual foot bone (not the ray start)
	var foot_world_y := (skel_xform * _global_pose(foot_idx).origin).y

	# Safety: if hit is way above foot, foot is deeply clipped — skip
	if heel_hit.y > foot_world_y + 0.1:
		return null

	var foot_pos := heel_hit + surface_n * ground_snap

	# Character forward = hip bone Y axis (Y-forward skeleton)
	var hip_basis := (skel_xform * _global_pose(idx_hips)).basis
	var char_fwd  := hip_basis.y.normalized()

	# Determine foot forward direction
	var foot_fwd: Vector3
	if toe_ray and toe_ray.is_colliding():
		var raw := toe_ray.get_collision_point() - heel_hit
		foot_fwd = raw.normalized() if raw.length_squared() > 0.001 else char_fwd
	else:
		foot_fwd = char_fwd

	# Right-handed basis: X = right, Y = forward, Z = up (surface normal)
	var right_v := foot_fwd.cross(surface_n)
	if right_v.length_squared() < 0.0001:
		right_v = char_fwd.cross(surface_n)
	if right_v.length_squared() < 0.0001:
		right_v = Vector3.RIGHT
	right_v  = right_v.normalized()
	foot_fwd = surface_n.cross(right_v).normalized()

	return Transform3D(Basis(right_v, foot_fwd, surface_n), foot_pos)


# ═══════════════════════════════════════════════════════════
# HIP DROP — world-Y → skeleton-local → parent-bone-local
# ═══════════════════════════════════════════════════════════
func _apply_hip_drop(r_target: Variant, l_target: Variant,
					 skel_xform: Transform3D):
	var r_delta := _drop_needed(r_target, idx_r_foot, skel_xform)
	var l_delta := _drop_needed(l_target, idx_l_foot, skel_xform)

	# Most-negative delta = the hip needs to drop the most
	var target_world_offset := minf(r_delta, l_delta)
	target_world_offset = clampf(target_world_offset, -hip_max_drop, 0.2)

	var dt := get_process_delta_time()
	_hip_offset = lerpf(_hip_offset, target_world_offset,
						clampf(hip_smooth_speed * dt, 0.0, 1.0))

	if absf(_hip_offset) < 0.0001:
		return

	# Convert world-Y offset through two frames to reach bone-local space
	var world_offset := Vector3(0.0, _hip_offset, 0.0)

	# Frame 1: undo skeleton node scale & rotation
	var skel_local := skel_xform.basis.inverse() * world_offset

	# Frame 2: undo hip's parent bone rotation (if any)
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


# ═══════════════════════════════════════════════════════════
# TWO-BONE IK — with proper knee pole direction
# ═══════════════════════════════════════════════════════════
func _solve_leg(thigh_idx: int, knee_idx: int, foot_idx: int,
				target_world: Transform3D, is_right: bool,
				skel_xform: Transform3D):

	var skel_scale := skel_xform.basis.get_scale().y
	var upper_len  := (r_upper_len if is_right else l_upper_len) * skel_scale
	var lower_len  := (r_lower_len if is_right else l_lower_len) * skel_scale
	var total_len  := upper_len + lower_len

	var thigh_pos := skel_xform * _global_pose(thigh_idx).origin
	var foot_pos  := target_world.origin

	var to_target := foot_pos - thigh_pos
	var dist := to_target.length()
	if dist < 0.0001:
		return
	var dir := to_target / dist

	# Prevent hyperextension & near-zero edge cases
	dist = clampf(dist, upper_len * 0.05, total_len * 0.98)

	# ── Law of cosines ──
	var cos_a := clampf(
		(upper_len * upper_len + dist * dist - lower_len * lower_len)
		/ (2.0 * upper_len * dist), -1.0, 1.0)
	var angle_a := acos(cos_a)

	# ── Knee pole direction ──
	# Use hip bone axes (Y-forward, X-right skeleton)
	var hip_basis  := (skel_xform * _global_pose(idx_hips)).basis
	var char_fwd   := hip_basis.y.normalized()
	var char_right := hip_basis.x.normalized()

	# ★ Slight outward bias per side so knees don't collapse inward
	var outward := char_right * (1.0 if is_right else -1.0) * knee_outward_bias

	# Combine forward + outward, then project onto plane ⊥ to leg direction
	var pole_dir := char_fwd + outward
	pole_dir -= dir * pole_dir.dot(dir)
	if pole_dir.length_squared() < 0.0001:
		pole_dir = skel_xform.basis.y.normalized()
		pole_dir -= dir * pole_dir.dot(dir)
	if pole_dir.length_squared() < 0.0001:
		pole_dir = Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.9 \
				   else Vector3.RIGHT
	pole_dir = pole_dir.normalized()

	# ★ Pole distance relative to upper leg length (not fixed world meters)
	var pole_dist := upper_len * knee_pole_forward
	var pole_pos  := (thigh_pos + foot_pos) * 0.5 + pole_dir * pole_dist

	# Rotation plane normal
	var to_pole := pole_pos - thigh_pos
	var plane_n := dir.cross(to_pole)
	if plane_n.length_squared() < 0.0001:
		plane_n = dir.cross(
			Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT)
	plane_n = plane_n.normalized()

	# Desired knee world position
	var desired_knee_pos := thigh_pos + dir.rotated(plane_n, angle_a) * upper_len

	# ── Apply rotations ──
	var knee_cur_pos := skel_xform * _global_pose(knee_idx).origin
	_rotate_bone_toward(thigh_idx, thigh_pos,
						knee_cur_pos, desired_knee_pos, skel_xform)

	var knee_new_pos := skel_xform * _global_pose(knee_idx).origin
	var foot_cur_pos := skel_xform * _global_pose(foot_idx).origin
	_rotate_bone_toward(knee_idx, knee_new_pos,
						foot_cur_pos, foot_pos, skel_xform)

	# Foot surface alignment (full override — see below)
	_rotate_foot_to_surface(foot_idx, target_world.basis, skel_xform)


# ═══════════════════════════════════════════════════════════
# BONE ROTATION HELPER — incremental axis-angle in parent space
# ═══════════════════════════════════════════════════════════
func _rotate_bone_toward(bone_idx: int,
						 bone_world: Vector3,
						 child_cur: Vector3, child_des: Vector3,
						 skel_xform: Transform3D):
	var from_dir := (child_cur - bone_world).normalized()
	var to_dir   := (child_des - bone_world).normalized()
	if from_dir.dot(to_dir) > 0.9999:
		return

	var world_axis := from_dir.cross(to_dir)
	if world_axis.length_squared() < 0.0001:
		return
	world_axis = world_axis.normalized()
	var angle := from_dir.angle_to(to_dir)

	# Axis into parent-bone-local space
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


# ═══════════════════════════════════════════════════════════
# FOOT SURFACE ALIGNMENT — ★ FULL OVERRIDE (not incremental)
#
# Why override instead of lerp:
#   The incremental quaternion approach only partially corrects the
#   foot angle each frame. If the animation has the foot tilted 40°
#   and we only correct 15° per frame, the foot looks "perked up"
#   permanently. Full override guarantees the sole is flat every frame.
#
# Why this is safe:
#   _foot_target() returns null when no ground contact → we skip
#   this function entirely → animation controls the foot in the air.
#   The only visual transition is at the contact edge, where
#   ground_snap provides a small natural buffer.
# ═══════════════════════════════════════════════════════════
func _rotate_foot_to_surface(foot_idx: int, target_world_basis: Basis,
							 skel_xform: Transform3D):
	var parent_idx := skeleton.get_bone_parent(foot_idx)

	# Get parent (knee) world transform AFTER all IK corrections
	var parent_world_xform: Transform3D
	if parent_idx >= 0:
		parent_world_xform = skel_xform * _global_pose(parent_idx)
	else:
		parent_world_xform = skel_xform

	# Derive the exact local basis needed so that:
	#   parent_world.basis × local_basis = target_world_basis
	var local_basis := parent_world_xform.basis.inverse() \
					   * target_world_basis.orthonormalized()

	var pose := skeleton.get_bone_pose(foot_idx)
	var original_scale := pose.basis.get_scale()

	# Full override — foot Z aligns to surface normal, guaranteed
	pose.basis = local_basis.orthonormalized().scaled(original_scale)
	skeleton.set_bone_pose(foot_idx, pose)


# ═══════════════════════════════════════════════════════════
# DEBUG DRAW
# ═══════════════════════════════════════════════════════════
func _debug_draw(skel_xform: Transform3D):
	# Leg segments
	for pair in [[idx_r_thigh, idx_r_knee], [idx_r_knee, idx_r_foot],
				 [idx_l_thigh, idx_l_knee], [idx_l_knee, idx_l_foot]]:
		var a := skel_xform * _global_pose(pair[0]).origin
		var b := skel_xform * _global_pose(pair[1]).origin
		DebugDraw3D.draw_line(a, b, Color.YELLOW)

	# Rays — show actual world direction
	for ray in [right_heel_ray, right_toe_ray, left_heel_ray, left_toe_ray]:
		if not ray:
			continue
		var world_end = ray.global_position + ray.global_basis * ray.target_position
		DebugDraw3D.draw_line(ray.global_position, world_end, Color.GREEN)
		# Small cyan sphere at ray start so you can see the offset
		DebugDraw3D.draw_sphere(ray.global_position, 0.02, Color.CYAN)
		if ray.is_colliding():
			DebugDraw3D.draw_sphere(ray.get_collision_point(), 0.03, Color.RED)

	# Hip axes for verification
	var hip_w := skel_xform * _global_pose(idx_hips)
	var hp := hip_w.origin
	DebugDraw3D.draw_line(hp, hp + hip_w.basis.z * 0.3, Color.BLUE)   # Z = up
	DebugDraw3D.draw_line(hp, hp + hip_w.basis.y * 0.3, Color.GREEN)  # Y = fwd
	DebugDraw3D.draw_line(hp, hp + hip_w.basis.x * 0.3, Color.RED)    # X = right
