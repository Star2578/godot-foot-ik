# FootIK Plugin for Godot 4

## Problem
In Godot 4, there is no foot IK addon that is easy to use without manually setting up a large number of nodes. Developers who need bipedal foot placement on uneven terrain have no plug-and-play solution out of the box.

## Approach

**Baseline:** Manually configuring multiple nodes and IK solvers in Godot 4 with no dedicated addon support for foot placement.

**Proposed:** Extend a `SkeletonModifier3D` node that solves bipedal foot placement on uneven terrain using a raycast-driven two-bone Inverse Kinematics (IK) approach combined with hip height compensation — fully plug-and-play with minimal setup required.

## Results

- **Speedup:** XX%
- **Stability Improvement:** XX%

### How to Install and use:
```
1. Copy only Foot_ik folder into res://addons/
2. Enable addon in project settings
3. Add FootIKController node as a child of your Skeleton3D node (Adjust Bone Names exports to match your rig if not using Mixamo defaults)
4. Create 4 RayCast3D node and assign all to FootIKController
5. Assign your CharacterBody3D to this node
6. Run a scene and tune ground_snap, hip_max_drop, knee_pole_forward to your character's proportions
```
