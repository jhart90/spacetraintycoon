"""Headless Blender asset generator (PLAN Phase 5 — the art pipeline, driven via
`blender --background --python` since the Blender MCP isn't reachable from this
session). Builds a low-poly train engine with PBR materials and exports a .glb
that Godot imports + renders, replacing the placeholder box.

Usage:
  blender --background --python gen_train_glb.py -- <out.glb>

This proves the swap path end-to-end. The full asset set (every engine/car/
planet/station, per PLAN §8) follows the same pattern, one .glb per asset.
"""
import bpy, sys, math

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out = argv[0] if argv else "train_engine.glb"

# Fresh scene.
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()

def _mat(name, color, metallic=0.6, rough=0.35):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    return m

def box(name, scale, loc, mat):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    o.data.materials.append(mat)
    return o

steel = _mat("steel", (0.20, 0.55, 0.85))
trim = _mat("trim", (0.15, 0.40, 0.70))
dark = _mat("dark", (0.10, 0.10, 0.12), metallic=0.2, rough=0.6)

box("body", (1.6, 0.7, 0.7), (0.0, 0.0, 0.4), steel)
box("cabin", (0.6, 0.62, 0.5), (0.55, 0.0, 0.95), trim)
box("chimney", (0.18, 0.18, 0.45), (-0.55, 0.0, 1.05), dark)
for i, (x, y) in enumerate([(0.5, 0.4), (0.5, -0.4), (-0.5, 0.4), (-0.5, -0.4)]):
    bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=0.12, location=(x, y, 0.0), rotation=(math.pi / 2, 0, 0))
    w = bpy.context.active_object
    w.name = "wheel%d" % i
    w.data.materials.append(dark)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True)
print("EXPORTED", out)
