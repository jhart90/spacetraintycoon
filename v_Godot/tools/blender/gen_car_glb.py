"""Headless Blender generator for a passenger CAR .glb (PLAN Phase 5).
  blender --background --python gen_car_glb.py -- <out.glb>
Same pipeline as gen_train_glb.py; one .glb per car type follows this template.
"""
import bpy, sys, math

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out = argv[0] if argv else "car_passenger.glb"

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()

def _mat(name, color, metallic=0.5, rough=0.4, emit=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    if emit is not None:
        b.inputs["Emission Color"].default_value = (emit[0], emit[1], emit[2], 1.0)
        b.inputs["Emission Strength"].default_value = 2.0
    return m

def box(name, scale, loc, mat):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    o.data.materials.append(mat)
    return o

shell = _mat("shell", (0.78, 0.80, 0.86))
roof = _mat("roof", (0.45, 0.50, 0.60))
windows = _mat("windows", (0.20, 0.85, 1.0), metallic=0.1, rough=0.1, emit=(0.1, 0.5, 0.7))
dark = _mat("dark", (0.10, 0.10, 0.12), metallic=0.2, rough=0.6)

box("body", (1.5, 0.66, 0.55), (0.0, 0.0, 0.4), shell)
box("roof", (1.45, 0.6, 0.16), (0.0, 0.0, 0.75), roof)
box("win_l", (1.3, 0.02, 0.22), (0.0, 0.34, 0.5), windows)
box("win_r", (1.3, 0.02, 0.22), (0.0, -0.34, 0.5), windows)
for i, (x, y) in enumerate([(0.45, 0.36), (0.45, -0.36), (-0.45, 0.36), (-0.45, -0.36)]):
    bpy.ops.mesh.primitive_cylinder_add(radius=0.2, depth=0.1, location=(x, y, 0.05), rotation=(math.pi / 2, 0, 0))
    bpy.context.active_object.data.materials.append(dark)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True)
print("EXPORTED", out)
