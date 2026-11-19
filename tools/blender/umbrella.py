"""Classic 8-rib stick umbrella (run: python3 tools/blender/umbrella.py -> assets/models/props/umbrella.glb).

Canopy: eight panels of fabric, each sagging a little between its ribs, scalloped at the edge, with a small cap at
the top. Ribs and stretchers in thin steel, rib-tip caps, a steel shaft with the runner, ferrule on top and a curved
wooden crook handle. The handle grip sits at the origin, shaft along +Y (Godot space).
Vertex data used by shaders/umbrella.gdshader:
  COLOR.r  = 1 on canopy fabric (0 frame)      COLOR.g = flutter weight (0 at ribs / centre, 1 mid-panel at the edge)
  COLOR.b  = radial distance from the shaft (m)   UV2.x  = part (0 fabric, 1 steel, 2 wood, 3 tip caps)
"""
import bpy, bmesh, math, os
from mathutils import Vector, Matrix

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, 'assets/models/props/umbrella.glb')

RIBS = 8
R = 0.56          # canopy radius (stretched open)
TOP = 0.98        # height of the canopy apex above the grip
DROP = 0.30       # how far the rim sits below the apex
SAG = 0.035       # fabric sag between ribs
SEG_R = 9         # rings from apex to rim
SEG_A = 6         # subdivisions across each panel


def G(x, y, z):
    return Vector((x, -z, y))


bm = bmesh.new()
col = bm.verts.layers.float_color.new('col')
part = bm.faces.layers.int.new('part')


def canopy_point(a, t):
    """a: angle around the shaft, t: 0 apex .. 1 rim. Returns Godot-space point + flutter weight."""
    # profile of a rib: a dome that flattens towards the rim
    rr = R * math.sin(t * math.pi * 0.5) ** 0.85
    y = TOP - DROP * (1.0 - math.cos(t * math.pi * 0.5)) - 0.02 * t
    # angle within the panel: 0 at a rib, 1 mid-panel
    k = (a / (2 * math.pi / RIBS)) % 1.0
    mid = math.sin(k * math.pi)
    # fabric pulls inwards and down between ribs, more towards the rim; the rim is scalloped
    rr *= 1.0 - 0.06 * mid * t
    y -= SAG * mid * t ** 1.5
    return Vector((math.cos(a) * rr, y, math.sin(a) * rr)), mid * t ** 2, rr


verts = {}
for i in range(SEG_R + 1):
    t = 0.04 + 0.96 * i / SEG_R
    for j in range(RIBS * SEG_A):
        a = 2 * math.pi * j / (RIBS * SEG_A)
        p, fw, rr = canopy_point(a, t)
        v = bm.verts.new(G(*p))
        v[col] = (1.0, fw, rr, 1.0)
        verts[(i, j)] = v
n = RIBS * SEG_A
for i in range(SEG_R):
    for j in range(n):
        f = bm.faces.new([verts[(i, j)], verts[(i, (j + 1) % n)], verts[(i + 1, (j + 1) % n)], verts[(i + 1, j)]])
        f[part] = 0
        f.smooth = True
# small cap closing the apex
apex = bm.verts.new(G(0, TOP + 0.012, 0))
apex[col] = (1.0, 0.0, 0.0, 1.0)
for j in range(n):
    f = bm.faces.new([apex, verts[(0, (j + 1) % n)], verts[(0, j)]])
    f[part] = 0
    f.smooth = True
bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])


def add_obj(ob, pid, rgb=(0.0, 0.0, 0.0)):
    dg = bpy.context.evaluated_depsgraph_get()
    me = ob.evaluated_get(dg).to_mesh()
    me.transform(ob.matrix_world)
    tmp = bmesh.new()
    tmp.from_mesh(me)
    ob.evaluated_get(dg).to_mesh_clear()
    bpy.data.objects.remove(ob, do_unlink=True)
    m = {}
    for v in tmp.verts:
        nv = bm.verts.new(v.co)
        rr = math.hypot(v.co.x, v.co.y)
        nv[col] = (0.0, 0.0, rr, 1.0)
        m[v.index] = nv
    for f in tmp.faces:
        try:
            nf = bm.faces.new([m[v.index] for v in f.verts])
            nf[part] = pid
            nf.smooth = f.smooth
        except ValueError:
            pass
    tmp.free()


def rod(p0, p1, r, verts=6):
    p0 = G(*p0)
    p1 = G(*p1)
    d = p1 - p0
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=d.length)
    ob = bpy.context.active_object
    ob.matrix_world = Matrix.Translation((p0 + p1) * 0.5) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


bpy.ops.wm.read_factory_settings(use_empty=True)
# shaft, runner and ferrule
add_obj(rod((0, 0.06, 0), (0, TOP + 0.01, 0), 0.0065, 10), 1)
add_obj(rod((0, TOP - 0.38, 0), (0, TOP - 0.31, 0), 0.012, 10), 1)
add_obj(rod((0, TOP + 0.01, 0), (0, TOP + 0.09, 0), 0.004, 8), 3)
# ribs just under the fabric, stretchers from the runner, tip caps
for k in range(RIBS):
    a = 2 * math.pi * k / RIBS
    prev = None
    for i in range(SEG_R + 1):
        t = 0.04 + 0.96 * i / SEG_R
        p, _, _ = canopy_point(a, t)
        p = p - Vector((0, 0.006, 0))
        if prev is not None:
            add_obj(rod(tuple(prev), tuple(p), 0.0028, 5), 1)
        prev = p
    tip, _, _ = canopy_point(a, 1.0)
    add_obj(rod(tuple(tip), tuple(tip + Vector((math.cos(a) * 0.018, -0.012, math.sin(a) * 0.018))), 0.0045, 6), 3)
    mid, _, _ = canopy_point(a, 0.55)
    add_obj(rod((0, TOP - 0.345, 0), tuple(mid - Vector((0, 0.008, 0))), 0.0022, 5), 1)
# crook handle: a straight grip down from the shaft into a J
pts = [Vector((0, 0.06, 0)), Vector((0, -0.06, 0))]
for i in range(1, 11):
    ang = math.pi * i / 10
    pts.append(Vector((0.045 - 0.045 * math.cos(ang), -0.06 - 0.045 * math.sin(ang), 0)))
for i in range(len(pts) - 1):
    add_obj(rod(tuple(pts[i]), tuple(pts[i + 1]), 0.012, 10), 2)

me = bpy.data.meshes.new('umbrella')
bm.normal_update()
bm.to_mesh(me)
ob = bpy.data.objects.new('umbrella', me)
bpy.context.scene.collection.objects.link(ob)
attr = me.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
cl = bm.verts.layers.float_color['col']
for i, v in enumerate(bm.verts):
    attr.data[i].color = v[cl]
uv0 = me.uv_layers.new(name='UVMap')
uv1 = me.uv_layers.new(name='UV2')
faces = list(bm.faces)
pl = bm.faces.layers.int['part']
for pi, p in enumerate(me.polygons):
    pid = faces[pi][pl]
    for li in p.loop_indices:
        co = me.vertices[me.loops[li].vertex_index].co
        uv0.data[li].uv = (math.atan2(co.y, co.x) / (2 * math.pi) * RIBS, math.hypot(co.x, co.y) * 4.0)
        uv1.data[li].uv = (float(pid), 0.0)
me.color_attributes.active_color = attr
for o in bpy.context.scene.objects:
    o.select_set(o == ob)
bpy.context.view_layer.objects.active = ob
bpy.ops.export_scene.gltf(filepath=OUT, use_selection=True, export_format='GLB', export_texcoords=True,
                          export_normals=True, export_vertex_color='ACTIVE', export_all_vertex_colors=True,
                          export_materials='NONE', export_yup=True)
print('OK', OUT, len(me.polygons))
