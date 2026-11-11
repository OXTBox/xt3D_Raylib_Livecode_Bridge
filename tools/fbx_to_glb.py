"""fbx_to_glb.py - convert a rigged, animated FBX (Mixamo and similar) to a GLB raylib can play.

Run with Blender (no window needed):
  blender --background --factory-startup --python fbx_to_glb.py -- in.fbx out.glb

Mixamo FBX files come into Blender with the armature object rotated 90 degrees and
scaled 0.01 (centimetres, Z up). The glTF exporter keeps that as a transform on the
Armature node, and raylib does not apply it to the animated pose: the model lies on
its face and/or the animation goes wrong. This script bakes the rotation and scale
into the bones and meshes, then scales the bones' location keys to match, so the
exported armature node has no transform at all.
"""
import sys
import bpy

args = sys.argv[sys.argv.index('--') + 1:]
src, out = args[0], args[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src)

rigs = [o for o in bpy.context.scene.objects if o.type == 'ARMATURE']
print('XT3D armatures:', [r.name for r in rigs])

for rig in rigs:
    factor = rig.scale[0]   # uniform in Mixamo files (0.01)
    print('XT3D', rig.name, 'rotation', tuple(rig.rotation_euler), 'scale', tuple(rig.scale))
    # Bake rotation and scale into the armature and every mesh it deforms.
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    for child in rig.children_recursive:
        child.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    # Bone location keys were in the old (unscaled) units: scale them to match.
    actions = set()
    if rig.animation_data and rig.animation_data.action:
        actions.add(rig.animation_data.action)
    for a in bpy.data.actions:
        actions.add(a)
    for action in actions:
        n = 0
        # Blender 4.4+ keeps f-curves in layered channelbags; older versions in action.fcurves
        curves = []
        if hasattr(action, 'layers') and len(action.layers):
            for layer in action.layers:
                for strip in layer.strips:
                    for bag in strip.channelbags:
                        curves.extend(bag.fcurves)
        else:
            curves = list(action.fcurves)
        for fc in curves:
            if fc.data_path.startswith('pose.bones') and fc.data_path.endswith('.location'):
                for kp in fc.keyframe_points:
                    kp.co[1] *= factor
                    kp.handle_left[1] *= factor
                    kp.handle_right[1] *= factor
                n += 1
        print('XT3D action', action.name, 'frames', tuple(action.frame_range), 'location curves scaled', n)

bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_skins=True,
                          export_animations=True, export_apply=False)
print('XT3D_WROTE', out)
