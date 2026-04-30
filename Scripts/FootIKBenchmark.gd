extends Node
class_name FootIKBenchmark

## Fair FootIK Benchmark - All methods do identical movement pattern

@export var character_body        : CharacterBody3D
@export var character_body_simple : CharacterBody3D
@export var animator_main         : AnimationTree
@export var animator_simple       : AnimationTree

@export var terrain_label         : String  = "flat"
@export var walk_speed            : float   = 2.0
@export var animation_blend       : float   = 10.0

@export var stand_frames          : int = 60
@export var walk_frames           : int = 120
@export var warmup_frames         : int = 120   # safer warmup

# ── Phases ────────────────────────────────────────────────────────────────────
enum Phase { BASELINE, SIMPLE, FOOTIK, DONE }
var _phase : Phase = Phase.BASELINE

enum TestState { STAND1, WALK_FORWARD, STAND2, WALK_BACK, STAND3 }
var _test_state : TestState = TestState.STAND1

var _sub_step : int = 0
var _warmup_counter : int = 0
var _is_warmup : bool = true

var _walk_dir : Vector3

var _mray_r : RayCast3D
var _mray_l : RayCast3D
const MRAY_LEN = 0.6
const MRAY_OFFSET = 0.05

var _skeleton : Skeleton3D
var _idx_r_foot : int
var _idx_l_foot : int

var _errors_r := { Phase.BASELINE: [], Phase.SIMPLE: [], Phase.FOOTIK: [] }
var _errors_l := { Phase.BASELINE: [], Phase.SIMPLE: [], Phase.FOOTIK: [] }
var _fps_data  := { Phase.BASELINE: [], Phase.SIMPLE: [], Phase.FOOTIK: [] }


func _ready():
	if not character_body or not character_body_simple:
		push_error("Missing character bodies"); return
	
	_walk_dir = Vector3.BACK.normalized()
	
	_activate_phase(Phase.BASELINE)


func _activate_phase(p: Phase):
	_phase = p
	_test_state = TestState.STAND1
	_sub_step = 0
	_warmup_counter = 0
	_is_warmup = true

	if _mray_r and is_instance_valid(_mray_r): _mray_r.queue_free()
	if _mray_l and is_instance_valid(_mray_l): _mray_l.queue_free()

	match p:
		Phase.BASELINE:
			print("→ Phase 1: BASELINE (No IK)")
			Manager.toggle_ik(true, false, false)
			_attach_skeleton(character_body.foot_ik_controller.skeleton)

		Phase.SIMPLE:
			print("→ Phase 2: SIMPLE IK")
			Manager.toggle_ik(false, true, false)
			# Enable benchmark mode on simple player
			if character_body_simple.has_method("set_benchmark_mode"):
				character_body_simple.set_benchmark_mode(true)
			var skel = character_body_simple.find_child("Skeleton3D", true, false) as Skeleton3D
			_attach_skeleton(skel)

		Phase.FOOTIK:
			print("→ Phase 3: FOOT IK CONTROLLER")
			Manager.toggle_ik(false, false, true)
			_attach_skeleton(character_body.foot_ik_controller.skeleton)

		Phase.DONE:
			# Disable benchmark mode
			if character_body_simple.has_method("set_benchmark_mode"):
				character_body_simple.set_benchmark_mode(false)
			_stop_all()
			_print_report()
			_write_csv()
			return


func _attach_skeleton(skel: Skeleton3D):
	_skeleton = skel
	var fikc = character_body.foot_ik_controller
	_idx_r_foot = _skeleton.find_bone(fikc.bone_right_foot)
	_idx_l_foot = _skeleton.find_bone(fikc.bone_left_foot)
	_mray_r = _make_mray("_mray_r", skel)
	_mray_l = _make_mray("_mray_l", skel)


func _make_mray(name: String, parent: Node3D) -> RayCast3D:
	var r = RayCast3D.new()
	r.name = name
	r.target_position = Vector3(0, -MRAY_LEN, 0)
	r.enabled = true
	r.exclude_parent = true
	parent.add_child(r)
	return r


func _stop_all():
	character_body.velocity = Vector3.ZERO
	character_body_simple.velocity = Vector3.ZERO


func _physics_process(delta: float):
	if _phase == Phase.DONE or not _skeleton:
		return

	_tick_test_sequence(delta)


func _tick_test_sequence(delta: float):
	var vel := Vector3.ZERO
	var is_walking := false

	match _test_state:
		TestState.STAND1, TestState.STAND2, TestState.STAND3:
			vel = Vector3.ZERO
		TestState.WALK_FORWARD:
			vel = _walk_dir * walk_speed
			is_walking = true
		TestState.WALK_BACK:
			vel = -_walk_dir * walk_speed
			is_walking = true

	# Movement
	character_body.velocity = vel
	character_body.move_and_slide()
	character_body_simple.velocity = vel
	character_body_simple.move_and_slide()

	# === SIMPLE IK SPECIFIC CONTROL ===
	if _phase == Phase.SIMPLE:
		# Force correct IK state: OFF when walking, ON when standing
		if character_body_simple.has_method("toggle_ik"):
			character_body_simple.toggle_ik(not is_walking)

	# Drive animation blend (this is safe for all)
	_drive_animator(animator_main,   vel, character_body.is_on_floor(), delta)
	_drive_animator(animator_simple, vel, character_body_simple.is_on_floor(), delta)

	# Warmup
	if _is_warmup:
		_warmup_counter += 1
		if _warmup_counter >= warmup_frames:
			_is_warmup = false
			print("  [%s] Warmup finished → Starting measurement" % Phase.keys()[_phase])
		return

	_sub_step += 1

	# State machine
	match _test_state:
		TestState.STAND1:
			if _sub_step >= stand_frames:
				_test_state = TestState.WALK_FORWARD
				_sub_step = 0
				print("  [%s] → Walking Forward" % Phase.keys()[_phase])

		TestState.WALK_FORWARD:
			if _sub_step >= walk_frames:
				_test_state = TestState.STAND2
				_sub_step = 0
				print("  [%s] → Standing (after forward)" % Phase.keys()[_phase])

		TestState.STAND2:
			if _sub_step >= stand_frames:
				_test_state = TestState.WALK_BACK
				_sub_step = 0
				print("  [%s] → Walking Back" % Phase.keys()[_phase])

		TestState.WALK_BACK:
			if _sub_step >= walk_frames:
				_test_state = TestState.STAND3
				_sub_step = 0
				print("  [%s] → Final Standing" % Phase.keys()[_phase])

		TestState.STAND3:
			if _sub_step >= stand_frames:
				if _phase == Phase.FOOTIK:
					_activate_phase(Phase.DONE)
				else:
					_activate_phase(Phase.values()[_phase + 1])
				return

	# Record data during walking + final stand
	if _test_state in [TestState.WALK_FORWARD, TestState.WALK_BACK, TestState.STAND3]:
		_record(_phase)


func _drive_animator(anim: AnimationTree, vel: Vector3, on_floor: bool, delta: float):
	if not anim: return
	if on_floor:
		anim.set("parameters/ground_air_transition/transition_request", "grounded")
		var target = -1.0 if vel.length() < 0.1 else 0.0
		var cur = anim.get("parameters/iwr_blend/blend_amount") as float
		anim.set("parameters/iwr_blend/blend_amount", lerpf(cur, target, delta * animation_blend))
	else:
		anim.set("parameters/ground_air_transition/transition_request", "air")


func _record(p: Phase):
	var skel_xform   := _skeleton.global_transform
	var r_foot_world := skel_xform * _foot_global_pose(_idx_r_foot)
	var l_foot_world := skel_xform * _foot_global_pose(_idx_l_foot)

	_mray_r.global_position = r_foot_world + Vector3(0, MRAY_OFFSET, 0)
	_mray_l.global_position = l_foot_world + Vector3(0, MRAY_OFFSET, 0)
	_mray_r.force_raycast_update()
	_mray_l.force_raycast_update()

	_errors_r[p].append(_foot_error(_mray_r, r_foot_world))
	_errors_l[p].append(_foot_error(_mray_l, l_foot_world))
	_fps_data[p].append(Engine.get_frames_per_second())

func _foot_global_pose(bone_idx: int) -> Vector3:
	var chain : Array[int] = []
	var idx   := bone_idx
	while idx >= 0:
		chain.push_front(idx)
		idx = _skeleton.get_bone_parent(idx)
	var xform := Transform3D.IDENTITY
	for i in chain:
		xform = xform * _skeleton.get_bone_pose(i)
	return xform.origin


func _foot_error(ray: RayCast3D, foot_world: Vector3) -> float:
	if not ray.is_colliding(): return 0.0
	return abs(foot_world.y - ray.get_collision_point().y) * 100.0


# ─────────────────────────────────────────────────────────────────────────────
func _avg(a: Array) -> float:
	if a.is_empty(): return 0.0
	var s := 0.0; 
	for v in a: s += float(v); 
	return s / a.size()

func _max_val(a: Array) -> float:
	if a.is_empty(): return 0.0
	var m := float(a[0]); 
	for v in a: if float(v) > m: m = float(v); 
	return m

func _pct_above(a: Array, t: float) -> float:
	if a.is_empty(): return 0.0
	var c := 0; for v in a: if float(v) > t: c += 1
	return float(c) / float(a.size()) * 100.0

func _improve(proposed: float, baseline: float) -> float:
	if baseline < 0.001: return 0.0
	return (baseline - proposed) / baseline * 100.0


# ─────────────────────────────────────────────────────────────────────────────
func _print_report():
	var avg_bl := (_avg(_errors_r[Phase.BASELINE]) + _avg(_errors_l[Phase.BASELINE])) / 2.0
	var avg_sm := (_avg(_errors_r[Phase.SIMPLE])   + _avg(_errors_l[Phase.SIMPLE]))   / 2.0
	var avg_fk := (_avg(_errors_r[Phase.FOOTIK])   + _avg(_errors_l[Phase.FOOTIK]))   / 2.0
	var max_bl := maxf(_max_val(_errors_r[Phase.BASELINE]), _max_val(_errors_l[Phase.BASELINE]))
	var max_sm := maxf(_max_val(_errors_r[Phase.SIMPLE]),   _max_val(_errors_l[Phase.SIMPLE]))
	var max_fk := maxf(_max_val(_errors_r[Phase.FOOTIK]),   _max_val(_errors_l[Phase.FOOTIK]))
	var fps_bl := _avg(_fps_data[Phase.BASELINE])
	var fps_sm := _avg(_fps_data[Phase.SIMPLE])
	var fps_fk := _avg(_fps_data[Phase.FOOTIK])
	var bad_bl := _pct_above(_errors_r[Phase.BASELINE] + _errors_l[Phase.BASELINE], 2.0)
	var bad_sm := _pct_above(_errors_r[Phase.SIMPLE]   + _errors_l[Phase.SIMPLE],   2.0)
	var bad_fk := _pct_above(_errors_r[Phase.FOOTIK]   + _errors_l[Phase.FOOTIK],   2.0)

	print("")
	print("╔════════════════════════════════════════════════════════════════════════╗")
	print("║                  FOOT IK BENCHMARK REPORT                             ║")
	print("╠════════════════════════════════════════════════════════════════════════╣")
	print("║  Terrain    : %-56s║" % terrain_label)
	print("║  Walk speed : %-56s║" % ("%.1f m/s" % walk_speed))
	print("║  NOTE: Simple IK measured while STANDING. Others measured WALKING.    ║")
	print("╠══════════════════╦════════════════╦════════════════╦══════════════════╣")
	print("║  FOOT Y ERROR    ║  Baseline      ║  Simple IK     ║  FootIKController║")
	print("║                  ║  (walking)     ║  (standing)    ║  (walking)       ║")
	print("╠══════════════════╬════════════════╬════════════════╬══════════════════╣")
	print("║  Avg both feet   ║   %7.2f cm   ║   %7.2f cm   ║   %7.2f cm     ║" % [avg_bl, avg_sm, avg_fk])
	print("║  Max error       ║   %7.2f cm   ║   %7.2f cm   ║   %7.2f cm     ║" % [max_bl, max_sm, max_fk])
	print("║  Frames > 2 cm   ║   %7.1f %%    ║   %7.1f %%    ║   %7.1f %%      ║" % [bad_bl, bad_sm, bad_fk])
	print("║  vs Baseline     ║       —        ║   %+7.1f %%    ║   %+7.1f %%      ║" % [_improve(avg_sm, avg_bl), _improve(avg_fk, avg_bl)])
	print("╠══════════════════╬════════════════╬════════════════╬══════════════════╣")
	print("║  Avg FPS         ║   %7.1f      ║   %7.1f      ║   %7.1f         ║" % [fps_bl, fps_sm, fps_fk])
	print("╠══════════════════╩════════════════╩════════════════╩══════════════════╣")
	print("║  COPY INTO REPORT TABLE:                                              ║")
	print("║  %-10s | BL %5.2fcm | Simple %5.2fcm (%+.1f%%) | FootIK %5.2fcm (%+.1f%%) ║"
		% [terrain_label, avg_bl, avg_sm, _improve(avg_sm, avg_bl), avg_fk, _improve(avg_fk, avg_bl)])
	print("╚════════════════════════════════════════════════════════════════════════╝\n")


func _write_csv():
	var fname := "user://foot_ik_bench_%s.csv" % terrain_label.replace(" ", "_")
	var f     := FileAccess.open(fname, FileAccess.WRITE)
	if not f:
		push_warning("FootIKBenchmark: could not write " + fname); return
	f.store_line("frame,method,error_right_cm,error_left_cm,fps")
	var labels := { Phase.BASELINE: "baseline", Phase.SIMPLE: "simple_ik", Phase.FOOTIK: "foot_ik" }
	for p in [Phase.BASELINE, Phase.SIMPLE, Phase.FOOTIK]:
		for i in (_errors_r[p] as Array).size():
			f.store_line("%d,%s,%.4f,%.4f,%.1f"
				% [i, labels[p], _errors_r[p][i], _errors_l[p][i], _fps_data[p][i]])
	f.close()
	print("  CSV → user://%s" % fname.get_file())
	print("  Windows: %%APPDATA%%\\Godot\\app_userdata\\<project>\\")
	print("  Linux  : ~/.local/share/godot/app_userdata/<project>/\n")