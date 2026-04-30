# FootIK Plugin for Godot 4

## Problem
In Godot 4, there is no foot IK addon that is easy to use without manually setting up a large number of nodes. Developers who need bipedal foot placement on uneven terrain have no plug-and-play solution out of the box.

## Approach

**Baseline:** Manually configuring multiple nodes and IK solvers in Godot 4 with no dedicated addon support for foot placement.

**Proposed:** Extend a `SkeletonModifier3D` node that solves bipedal foot placement on uneven terrain using a raycast-driven two-bone Inverse Kinematics (IK) approach combined with hip height compensation — fully plug-and-play with minimal setup required.

## Project Structure

```
godot-foot-ik/
├── addons/
│   ├── foot_ik/                    # Main FootIK addon
│   │   ├── foot_ik_controller.gd
│   │   ├── plugin.gd
│   │   ├── plugin.cfg
│   │   └── icon.svg.import
│   ├── debug_draw_3d/              # Debug visualization addon
│   └── terrain_3d/                 # Terrain plugin
├── Assets/
│   ├── Animations/                 # Character animations
│   ├── Models/                     # 3D models
│   └── Textures/                   # Texture assets
├── Scenes/
│   ├── Characters/                 # Character scene files
│   ├── Levels/                      # Level scenes
│   └── Tests/                       # Test scenes
├── Scripts/
│   ├── Characters/                 # Character scripts
│   ├── FootIKBenchmark.gd
│   ├── FootIKModifier.gd
│   ├── Manager.gd
│   └── test_interface.gd
└── terrain/                        # Terrain data files
```

## Installation & Setup

### Option 1: Clone or Download the Addon
Clone or download the entire repository, then copy only the `addons/foot_ik` folder into your Godot project:

```bash
# Clone the entire repo
git clone <repository-url> godot-foot-ik

# Copy the foot_ik addon to your project
cp -r godot-foot-ik/addons/foot_ik your-project/addons/
```

Or manually download the `addons/foot_ik` folder from the repository and place it in your project's `addons/` directory.

### How to Use:
1. Copy only the `foot_ik` folder into `res://addons/` of your Godot project
2. Enable the addon in **Project > Project Settings > Plugins** and check the "Foot IK" plugin
3. Add a `FootIKController` node as a child of your `Skeleton3D` node
   - Adjust **Bone Names** exports to match your rig (defaults are Mixamo skeleton names)
4. Assign your `CharacterBody3D` reference to the FootIKController
5. Run a scene and tune these parameters to your character's proportions:
   - `ground_snap`: How much to snap feet to ground
   - `hip_max_drop`: Maximum hip drop distance
   - `knee_pole_forward`: Knee pole vector direction
