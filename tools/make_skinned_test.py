"""make_skinned_test.py - build a tiny skinned, animated GLB for testing xt3d animation.

Run with Blender (no window needed):
  blender --background --factory-startup --python make_skinned_test.py -- out.glb

Makes one cylinder mesh (a single skinned mesh, which is what raylib needs),
an armature of 3 bones in a column, and one 48-frame action "Bend" that bends
the column left and right. Exports as GLB with the skin and the animation.
"""
import sys, math
import bpy

out = sys.argv[sys.argv.index('--') + 1] if '--' in sys.argv else 'skinned_test.glb'

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.frame_start, scene.frame_end = 1, 48

# Mesh: an upright cylinder, 3 units tall, with enough rings to bend smoothly.
bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.35, depth=3.0, location=(0, 0, 1.5))
body = bpy.context.active_object
body.name = 'Column'
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.subdivide(number_cuts=11)
bpy.ops.object.mode_set(mode='OBJECT')

# Armature: three bones stacked along Z.
bpy.ops.object.armature_add(location=(0, 0, 0))
rig = bpy.context.active_object
rig.name = 'Rig'
bpy.ops.object.mode_set(mode='EDIT')
eb = rig.data.edit_bones
first = eb[0]; first.name = 'Bone0'; first.head = (0, 0, 0); first.tail = (0, 0, 1)
parent = first
for i in (1, 2):
    b = eb.new('Bone%d' % i)
    b.head = (0, 0, i); b.tail = (0, 0, i + 1)
    b.parent = parent; b.use_connect = True
    parent = b
bpy.ops.object.mode_set(mode='OBJECT')

# Skin: parent with automatic weights.
bpy.ops.object.select_all(action='DESELECT')
body.select_set(True); rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type='ARMATURE_AUTO')

# Animation: bend each bone around Y, left then right.
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='POSE')
for frame, angle in ((1, 0), (13, 30), (25, 0), (37, -30), (48, 0)):
    for pb in rig.pose.bones:
        pb.rotation_mode = 'XYZ'
        pb.rotation_euler = (0, math.radians(angle), 0)
        pb.keyframe_insert('rotation_euler', frame=frame)
bpy.ops.object.mode_set(mode='OBJECT')
if rig.animation_data and rig.animation_data.action:
    rig.animation_data.action.name = 'Bend'

bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_skins=True,
                          export_animations=True, export_apply=False)
print('XT3D_WROTE', out)
