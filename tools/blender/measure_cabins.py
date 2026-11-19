"""Measure the cabin of every vehicle (run with python3 + bpy).
Imports assets exported from Godot (/home/claude/work/veh/*.glb), ray-casts the body to find the floor, roof,
windscreen and rear window, and writes data/vehicle_cabins.json in Godot model space (x right, y up, z back).
"""
import bpy, bmesh, json, os, sys, glob
from mathutils import Vector
from mathutils.bvhtree import BVHTree

SRC = sys.argv[1] if len(sys.argv) > 1 else '/home/claude/work/veh'
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'data/vehicle_cabins.json')


def g2b(v):  # godot (x, y, z) -> blender (x, -z, y)
    return Vector((v[0], -v[2], v[1]))


def b2g(v):
    return [round(v.x, 4), round(v.z, 4), round(-v.y, 4)]


res = {}
for path in sorted(glob.glob(os.path.join(SRC, '*.glb'))):
    name = os.path.basename(path)[:-4]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    ob = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.transform(ob.matrix_world)
    uv2 = bm.loops.layers.uv[1] if len(bm.loops.layers.uv) > 1 else None
    glass_faces = []
    for f in bm.faces:
        if uv2 is not None:
            p = int(round(f.loops[0][uv2].uv.x))
            if p == 1:
                glass_faces.append(f)
    tree = BVHTree.FromBMesh(bm)
    # glass extents
    gv = [v.co for f in glass_faces for v in f.verts]
    gmin = Vector((min(v.x for v in gv), min(v.y for v in gv), min(v.z for v in gv)))
    gmax = Vector((max(v.x for v in gv), max(v.y for v in gv), max(v.z for v in gv)))
    # in godot terms: z_g = -y_b
    prof = []
    z = -3.6
    while z <= 3.6:
        row = {'z': round(z, 2)}
        for x in (-0.4, 0.0, 0.4):
            o = g2b((x, 1.0, z))
            hu = tree.ray_cast(o, Vector((0, 0, 1)), 3.0)
            hd = tree.ray_cast(o, Vector((0, 0, -1)), 2.0)
            row['roof%+.1f' % x] = round(hu[0].z, 3) if hu[0] else None
            row['floor%+.1f' % x] = round(hd[0].z, 3) if hd[0] else None
        prof.append(row)
        z += 0.1
    # side wall: from the centre line at belt height, cast left and right
    walls = []
    for zz in (-0.6, 0.0, 0.6, 1.2):
        o = g2b((0.0, gmin.z - 0.12, zz))
        hl = tree.ray_cast(o, Vector((-1, 0, 0)), 2.0)
        hr = tree.ray_cast(o, Vector((1, 0, 0)), 2.0)
        walls.append([zz, round(hl[0].x, 3) if hl[0] else None, round(hr[0].x, 3) if hr[0] else None])
    res[name] = {'glass_min': b2g(Vector((gmin.x, gmax.y, gmin.z))), 'glass_max': b2g(Vector((gmax.x, gmin.y, gmax.z))),
                 'walls': walls, 'profile': prof}
    print(name, res[name]['glass_min'], res[name]['glass_max'], walls)
    bm.free()

json.dump(res, open(OUT, 'w'), indent=0)
