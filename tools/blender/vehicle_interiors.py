"""Vehicle interiors (run: python3 tools/blender/vehicle_interiors.py [model ...]).

Builds a cabin for every vehicle from data/vehicle_cabins.json (measured by measure_cabins.py): seats with soft
cushions and bolsters, dashboard with instruments and centre stack, steering wheel, centre console with gear lever,
door cards, carpet, and per type extras (police cage + laptop, taxi partition + meter, limousine lounge with wood and
leather, utility bulkheads for vans and trucks). Each type gets its own design and trim, not one interior for all.

Output: /home/claude/work/interiors/<model>.glb, one mesh, Godot model space (x right, y up, front = -z,
driver on -x). Attributes: TEXCOORD_1.x = vehicle.gdshader part id, COLOR_0 = albedo (rgb) + baked occlusion (a),
TEXCOORD_0 = metres along the surface (for fabric / stitch / grain patterns).
"""
import bpy, bmesh, json, math, os, sys
from mathutils import Vector, Matrix

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = '/home/claude/work/interiors'
CAB = json.load(open(os.path.join(ROOT, 'data/vehicle_cabins.json')))

# vehicle.gdshader part ids for interior materials
CLOTH, LEATHER, PLASTIC, RUBBER, HEADLINER, WOOD, GAUGE, CARPET, METAL, VINYL, SCREEN = 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28


def G(x, y, z):
    """Godot model coordinates -> Blender (the glTF exporter turns Blender Z-up back into Y-up)."""
    return Vector((x, -z, y))


class Kit:
    def __init__(self):
        self.bm = bmesh.new()
        self.part = self.bm.faces.layers.int.new('part')
        self.col = self.bm.verts.layers.float_color.new('col')

    def add_object(self, ob, part, color, ao_top=0.8, ao_bottom=0.45, y0=None, y1=None):
        dg = bpy.context.evaluated_depsgraph_get()
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        me.transform(ob.matrix_world)
        tmp = bmesh.new()
        tmp.from_mesh(me)
        ev.to_mesh_clear()
        bpy.data.objects.remove(ob, do_unlink=True)
        zs = [v.co.z for v in tmp.verts] or [0.0]
        lo = min(zs) if y0 is None else y0
        hi = max(zs) if y1 is None else y1
        vmap = {}
        for v in tmp.verts:
            nv = self.bm.verts.new(v.co)
            k = 0.0 if hi - lo < 1e-4 else min(max((v.co.z - lo) / (hi - lo), 0.0), 1.0)
            ao = ao_bottom + (ao_top - ao_bottom) * k
            nv[self.col] = (color[0], color[1], color[2], ao)
            vmap[v.index] = nv
        for f in tmp.faces:
            try:
                nf = self.bm.faces.new([vmap[v.index] for v in f.verts])
                nf[self.part] = part
                nf.smooth = f.smooth
            except ValueError:
                pass
        tmp.free()

    def finish(self, name):
        me = bpy.data.meshes.new(name)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        # UV0: box projection in metres; UV1 (TEXCOORD_1): part id
        uv0 = me.uv_layers.new(name='UVMap')
        uv1 = me.uv_layers.new(name='UV2')
        attr = me.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
        cl = self.bm.verts.layers.float_color['col']
        bm2 = bmesh.new()
        bm2.from_mesh(me)
        for p in me.polygons:
            n = p.normal
            ax = max(range(3), key=lambda i: abs(n[i]))
            pid = p.material_index
        for i, v in enumerate(self.bm.verts):
            attr.data[i].color = v[cl]
        part_layer = self.bm.faces.layers.int['part']
        faces = list(self.bm.faces)
        for pi, p in enumerate(me.polygons):
            pid = faces[pi][part_layer]
            n = p.normal
            ax = max(range(3), key=lambda i: abs(n[i]))
            for li in p.loop_indices:
                co = me.vertices[me.loops[li].vertex_index].co
                if ax == 0:
                    u, v = co.y, co.z
                elif ax == 1:
                    u, v = co.x, co.z
                else:
                    u, v = co.x, co.y
                uv0.data[li].uv = (u, v)
                uv1.data[li].uv = (float(pid), 0.0)
        me.color_attributes.active_color = attr
        bm2.free()
        return ob


def box(c, s, bevel=0.0, seg=2, subsurf=0, rot=None, smooth=True):
    """c, s in Godot coords (centre, full size). rot: (axis 'x'/'y'/'z' in Godot space, degrees) or list of them."""
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    ob = bpy.context.active_object
    ob.scale = (s[0], s[2], s[1])
    bpy.ops.object.transform_apply(scale=True)
    if bevel > 0.0:
        m = ob.modifiers.new('b', 'BEVEL')
        m.width = bevel
        m.segments = min(seg, 1 if subsurf else 2)
        m.limit_method = 'NONE'
    if subsurf:
        m = ob.modifiers.new('s', 'SUBSURF')
        m.levels = subsurf
    rots = rot if isinstance(rot, list) else ([rot] if rot else [])
    mat = Matrix.Identity(4)
    for axis, deg in rots:
        bax = {'x': 'X', 'y': 'Z', 'z': 'Y'}[axis]
        sign = -1.0 if axis == 'z' else 1.0
        mat = Matrix.Rotation(math.radians(deg) * sign, 4, bax) @ mat
    ob.matrix_world = Matrix.Translation(G(*c)) @ mat
    if smooth:
        for p in ob.data.polygons:
            p.use_smooth = True
    return ob


def cyl(c, r, length, axis='x', verts=16, rot=None, depth_cap=True):
    bpy.ops.mesh.primitive_cylinder_add(vertices=max(6, min(verts, 14)), radius=r, depth=length)
    ob = bpy.context.active_object
    base = {'x': Matrix.Rotation(math.radians(90), 4, 'Y'), 'y': Matrix.Identity(4), 'z': Matrix.Rotation(math.radians(90), 4, 'X')}[axis]
    mat = base
    rots = rot if isinstance(rot, list) else ([rot] if rot else [])
    for ax, deg in rots:
        bax = {'x': 'X', 'y': 'Z', 'z': 'Y'}[ax]
        sign = -1.0 if ax == 'z' else 1.0
        mat = Matrix.Rotation(math.radians(deg) * sign, 4, bax) @ mat
    ob.matrix_world = Matrix.Translation(G(*c)) @ mat
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def torus(c, R, r, tilt_deg):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=24, minor_segments=8)
    ob = bpy.context.active_object
    # wheel plane faces the driver (+z, back) tilted back by tilt_deg from vertical
    mat = Matrix.Rotation(math.radians(90 - tilt_deg), 4, 'X')
    ob.matrix_world = Matrix.Translation(G(*c)) @ mat
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


# --------------------------------------------------------------------------------------------------------- pieces
def seat(kit, x, z, floor, style, colr, w=0.5):
    """Front seat. style: cloth / sport / leather / vinyl / bench_police."""
    part = {'cloth': CLOTH, 'sport': CLOTH, 'leather': LEATHER, 'vinyl': VINYL}.get(style, CLOTH)
    h = floor + 0.25
    # rails and base
    kit.add_object(box((x, floor + 0.07, z + 0.02), (w * 0.8, 0.12, 0.42), 0.01), PLASTIC, (0.03, 0.03, 0.03), 0.4, 0.2)
    # cushion: soft, slightly raised at the front
    kit.add_object(box((x, h - 0.05, z), (w, 0.12, 0.5), 0.05, 3, 1, ('x', -4)), part, colr, 0.75, 0.45)
    bol = style in ('sport', 'leather')
    if bol:
        for sx in (-1, 1):
            kit.add_object(box((x + sx * (w * 0.5 - 0.035), h + 0.0, z + 0.02), (0.07, 0.09, 0.46), 0.03, 3, 1), part, colr, 0.75, 0.5)
    # backrest leaning back 18 degrees, pivot at the rear of the cushion
    bz = z + 0.27
    by = h + 0.29
    kit.add_object(box((x, by, bz + 0.09), (w, 0.62, 0.11), 0.045, 3, 1, ('x', -18)), part, colr, 0.8, 0.5)
    if bol:
        for sx in (-1, 1):
            kit.add_object(box((x + sx * (w * 0.5 - 0.03), by - 0.03, bz + 0.06), (0.07, 0.5, 0.15), 0.03, 3, 1, ('x', -18)), part, colr, 0.8, 0.5)
    # headrest on two posts
    hy = by + 0.39
    hz = bz + 0.21
    kit.add_object(box((x, hy, hz), (0.26, 0.17, 0.09), 0.035, 3, 1, ('x', -12)), part, colr, 0.85, 0.6)
    for sx in (-0.07, 0.07):
        kit.add_object(cyl((x + sx, hy - 0.11, hz - 0.01), 0.007, 0.08, 'y', 8), METAL, (0.5, 0.5, 0.52), 0.8, 0.8)


def bench(kit, z, floor, half, style, colr, headrests=3, back_h=0.55):
    part = {'cloth': CLOTH, 'leather': LEATHER, 'vinyl': VINYL}.get(style, CLOTH)
    h = floor + 0.24
    w = half * 2 - 0.08
    kit.add_object(box((0, h - 0.06, z), (w, 0.13, 0.48), 0.05, 3, 1, ('x', -5)), part, colr, 0.72, 0.4)
    kit.add_object(box((0, h + 0.26, z + 0.31), (w, back_h, 0.12), 0.05, 3, 1, ('x', -21)), part, colr, 0.78, 0.45)
    if style != 'vinyl':
        # seams between the seat places
        for sx in (-w / 6, w / 6):
            kit.add_object(box((sx, h + 0.0, z), (0.012, 0.13, 0.46), 0.0), part, tuple(c * 0.6 for c in colr), 0.6, 0.4)
    xs = [-0.42, 0.0, 0.42][:headrests] if headrests == 3 else [-0.42, 0.42]
    for sx in xs:
        kit.add_object(box((sx, h + 0.6, z + 0.45), (0.24, 0.14, 0.08), 0.03, 3, 1, ('x', -14)), part, colr, 0.85, 0.6)


def dashboard(kit, ws_z, belt, half, floor, style, colr, trim=None):
    """Dash from the windscreen base back towards the driver. style: classic / sport / utility / luxury."""
    top = belt + 0.02
    depth = 0.46 if style != 'utility' else 0.4
    w = half * 2 - 0.02
    # main body: slab with a rounded leading edge
    kit.add_object(box((0, top - 0.09, ws_z + depth * 0.5), (w, 0.18, depth), 0.05, 3, 1), PLASTIC, colr, 0.6, 0.35)
    # lower dash / knee bolster
    kit.add_object(box((0, top - 0.3, ws_z + depth * 0.62), (w, 0.26, depth * 0.55), 0.04, 2, 0, ('x', 14)), PLASTIC, tuple(c * 0.8 for c in colr), 0.4, 0.2)
    # instrument hood over the gauges (driver side, -x)
    kit.add_object(box((-0.4, top + 0.04, ws_z + depth - 0.08), (0.44, 0.07, 0.16), 0.035, 3, 1), PLASTIC, colr, 0.6, 0.4)
    # gauges: round dials (classic / sport) or a bar (utility)
    gz = ws_z + depth - 0.005
    if style in ('classic', 'luxury', 'sport'):
        n = 2 if style != 'sport' else 3
        for i in range(n):
            gx = -0.4 + (i - (n - 1) / 2) * (0.15 if n == 2 else 0.11)
            r = 0.058 if n == 2 else 0.045
            kit.add_object(cyl((gx, top - 0.025, gz), r, 0.01, 'z', 24), GAUGE, (0.9, 0.9, 0.85), 0.9, 0.9)
            kit.add_object(cyl((gx, top - 0.025, gz - 0.006), r + 0.008, 0.012, 'z', 24), METAL, (0.55, 0.55, 0.58), 0.8, 0.8)
    else:
        kit.add_object(box((-0.4, top - 0.03, gz), (0.3, 0.07, 0.008), 0.0), GAUGE, (0.85, 0.85, 0.8), 0.9, 0.9)
    # centre stack: radio, climate, vents
    kit.add_object(box((0.0, top - 0.17, ws_z + depth + 0.01), (0.22, 0.28, 0.04), 0.012, 2), PLASTIC, tuple(c * 0.75 for c in colr), 0.6, 0.4)
    kit.add_object(box((0.0, top - 0.11, ws_z + depth + 0.033), (0.16, 0.045, 0.008), 0.0), SCREEN, (0.2, 0.55, 0.9), 0.9, 0.9)
    for vx in (-0.06, 0.06):
        kit.add_object(box((vx, top - 0.035, ws_z + depth + 0.032), (0.09, 0.04, 0.01), 0.004), RUBBER, (0.02, 0.02, 0.02), 0.5, 0.5)
    for vx in (-half + 0.12, half - 0.12):
        kit.add_object(cyl((vx, top - 0.05, ws_z + depth - 0.02), 0.04, 0.03, 'z', 16), RUBBER, (0.02, 0.02, 0.02), 0.5, 0.5)
    if trim is not None:
        # decorative strip across the dash (wood / aluminium)
        kit.add_object(box((0.22, top - 0.13, ws_z + depth + 0.008), (half - 0.2, 0.04, 0.012), 0.004), trim[0], trim[1], 0.8, 0.8)
    # glovebox line
    kit.add_object(box((0.42, top - 0.22, ws_z + depth * 0.78 + 0.035), (0.36, 0.006, 0.006), 0.0), RUBBER, (0.01, 0.01, 0.01), 0.4, 0.4)


def steering(kit, ws_z, belt, style, colr):
    x = -0.4
    z = ws_z + 0.62
    y = belt - 0.02
    tilt = 24 if style != 'utility' else 36   # buses / vans have flatter wheels
    R = 0.19 if style != 'sport' else 0.175
    kit.add_object(torus((x, y, z), R, 0.017 if style != 'sport' else 0.021, tilt), RUBBER, (0.025, 0.022, 0.02), 0.6, 0.6)
    # hub
    kit.add_object(cyl((x, y, z - 0.02), 0.055, 0.05, 'z', 20, ('x', -tilt)), PLASTIC, colr, 0.6, 0.6)
    # spokes
    n = {'classic': 2, 'luxury': 4, 'sport': 3, 'utility': 4, 'police': 4}.get(style, 3)
    angs = {2: [0, 180], 3: [90, 210, 330], 4: [30, 150, 210, 330]}[n]
    if n == 2:
        angs = [10, 170]
    for a in angs:
        ar = math.radians(a)
        lx = math.cos(ar) * R * 0.55
        ly = math.sin(ar) * R * 0.55
        # in the wheel plane: x stays, y tilts with the wheel
        ty = ly * math.cos(math.radians(tilt))
        tz = -ly * math.sin(math.radians(tilt))
        kit.add_object(box((x + lx, y + ty, z + tz - 0.01), (R * 0.95 if abs(math.cos(ar)) > 0.5 else 0.035, 0.03 if abs(math.cos(ar)) > 0.5 else R * 0.9, 0.018), 0.008, 2, 0,
                           [('x', -tilt), ('z', a if abs(math.cos(ar)) > 0.5 else 0)]), PLASTIC, colr, 0.6, 0.6)
    # column to the dash
    kit.add_object(cyl((x, y - 0.09, z - 0.17), 0.035, 0.32, 'z', 12, ('x', -tilt - 6)), PLASTIC, tuple(c * 0.7 for c in colr), 0.5, 0.4)


def console(kit, ws_z, floor, belt, length, colr, style):
    z0 = ws_z + 0.42
    kit.add_object(box((0, floor + 0.16, z0 + length * 0.5), (0.22, 0.3, length), 0.03, 2), PLASTIC, colr, 0.6, 0.3)
    # gear lever with a knob
    kit.add_object(cyl((0, floor + 0.38, z0 + 0.28), 0.012, 0.16, 'y', 10, ('x', 12)), METAL if style == 'sport' else PLASTIC, (0.15, 0.15, 0.15), 0.7, 0.6)
    kit.add_object(cyl((0, floor + 0.47, z0 + 0.3), 0.022, 0.045, 'y', 14), LEATHER if style in ('sport', 'luxury') else PLASTIC, (0.03, 0.03, 0.03), 0.7, 0.7)
    # armrest lid
    kit.add_object(box((0, floor + 0.33, z0 + length - 0.15), (0.2, 0.05, 0.28), 0.02, 2, 1), LEATHER if style == 'luxury' else PLASTIC, colr, 0.7, 0.6)


def door_cards(kit, z0, z1, floor, belt, half, colr, insert, insert_part):
    for sx in (-1, 1):
        x = sx * (half - 0.015)
        kit.add_object(box((x, (floor + belt) * 0.5, (z0 + z1) * 0.5), (0.03, belt - floor, z1 - z0), 0.01), PLASTIC, colr, 0.7, 0.3)
        # armrest and the fabric / leather insert above it
        kit.add_object(box((x - sx * 0.04, floor + 0.38, (z0 + z1) * 0.5), (0.07, 0.05, (z1 - z0) * 0.8), 0.015, 2), PLASTIC, tuple(c * 0.8 for c in colr), 0.7, 0.6)
        kit.add_object(box((x - sx * 0.02, floor + 0.5, (z0 + z1) * 0.5), (0.012, 0.16, (z1 - z0) * 0.75), 0.005), insert_part, insert, 0.75, 0.6)


def floor_carpet(kit, z0, z1, floor, half, colr):
    kit.add_object(box((0, floor, (z0 + z1) * 0.5), (half * 2 - 0.02, 0.02, z1 - z0), 0.0, 1, 0, None, False), CARPET, colr, 0.35, 0.35)


def bulkhead(kit, z, floor, top, half, colr, window=True):
    kit.add_object(box((0, (floor + top) * 0.5, z), (half * 2 - 0.02, top - floor, 0.04), 0.0), PLASTIC, colr, 0.5, 0.3)


def police_cage(kit, z, floor, top, half):
    # steel frame with a polycarbonate window and vertical bars over the lower half
    kit.add_object(box((0, floor + 0.35, z), (half * 2 - 0.04, 0.5, 0.025), 0.0), METAL, (0.05, 0.05, 0.055), 0.5, 0.4)
    for i in range(9):
        bx = -half + 0.12 + i * (2 * half - 0.24) / 8
        kit.add_object(cyl((bx, (floor + 0.6 + top) * 0.5, z), 0.009, top - floor - 0.62, 'y', 8), METAL, (0.08, 0.08, 0.085), 0.6, 0.6)
    kit.add_object(box((0, top - 0.02, z), (half * 2 - 0.04, 0.04, 0.04), 0.005), METAL, (0.05, 0.05, 0.055), 0.6, 0.6)


def laptop(kit, ws_z, belt):
    # mobile data terminal on a pole at the passenger side of the console
    kit.add_object(cyl((0.12, belt - 0.2, ws_z + 0.72), 0.015, 0.3, 'y', 10), METAL, (0.1, 0.1, 0.1), 0.6, 0.5)
    kit.add_object(box((0.12, belt - 0.03, ws_z + 0.74), (0.32, 0.02, 0.22), 0.005, 1, 0, ('x', 8)), PLASTIC, (0.03, 0.03, 0.03), 0.7, 0.7)
    kit.add_object(box((0.12, belt + 0.09, ws_z + 0.86), (0.3, 0.2, 0.012), 0.004, 1, 0, ('x', -12)), SCREEN, (0.35, 0.7, 1.0), 0.9, 0.9)
    # radio head on the dash
    kit.add_object(box((0.0, belt - 0.24, ws_z + 0.5), (0.18, 0.06, 0.06), 0.008), PLASTIC, (0.02, 0.02, 0.02), 0.6, 0.6)


def taxi_partition(kit, z, floor, belt, top, half):
    kit.add_object(box((0, (floor + belt) * 0.5 + 0.02, z), (half * 2 - 0.04, belt - floor, 0.03), 0.004), PLASTIC, (0.04, 0.04, 0.04), 0.5, 0.3)
    kit.add_object(box((0, belt + 0.02, z), (half * 2 - 0.04, 0.04, 0.05), 0.006), METAL, (0.45, 0.45, 0.47), 0.7, 0.7)
    for sx in (-half + 0.05, 0.0, half - 0.05):
        kit.add_object(box((sx, (belt + top) * 0.5, z), (0.03, top - belt, 0.03), 0.004), METAL, (0.45, 0.45, 0.47), 0.7, 0.7)
    # payment slot and the card reader
    kit.add_object(box((0.18, belt + 0.06, z - 0.03), (0.16, 0.1, 0.04), 0.006), PLASTIC, (0.03, 0.03, 0.03), 0.7, 0.7)


def taxi_meter(kit, ws_z, belt):
    kit.add_object(box((0.12, belt + 0.07, ws_z + 0.36), (0.16, 0.06, 0.08), 0.008), PLASTIC, (0.02, 0.02, 0.02), 0.7, 0.7)
    kit.add_object(box((0.12, belt + 0.075, ws_z + 0.402), (0.12, 0.03, 0.004), 0.0), SCREEN, (1.0, 0.25, 0.1), 0.9, 0.9)


def limo_lounge(kit, z0, z1, floor, belt, half, leather, wood):
    # rear-facing bench behind the partition, a long side bench on the right, a bar on the left, a rear bench
    kit.add_object(box((0, (floor + belt + 0.3) * 0.5, z0), (half * 2 - 0.04, belt + 0.3 - floor, 0.06), 0.01), WOOD, wood, 0.6, 0.4)
    bench(kit, z1 - 0.38, floor, half, 'leather', leather, 2, 0.52)
    side_z = (z0 + z1) * 0.5
    x = half - 0.27
    kit.add_object(box((x, floor + 0.2, side_z + 0.15), (0.44, 0.12, z1 - z0 - 1.25), 0.05, 3, 1), LEATHER, leather, 0.72, 0.45)
    kit.add_object(box((half - 0.07, floor + 0.47, side_z + 0.15), (0.1, 0.48, z1 - z0 - 1.25), 0.04, 3, 1), LEATHER, leather, 0.78, 0.5)
    # bar cabinet: wood with a brushed steel top
    kit.add_object(box((-half + 0.2, floor + 0.28, side_z), (0.3, 0.5, 1.0), 0.015), WOOD, wood, 0.6, 0.35)
    kit.add_object(box((-half + 0.2, floor + 0.535, side_z), (0.31, 0.012, 1.01), 0.004), METAL, (0.6, 0.6, 0.62), 0.8, 0.8)
    for i in range(3):
        kit.add_object(cyl((-half + 0.2, floor + 0.6, side_z - 0.25 + i * 0.25), 0.03, 0.12, 'y', 12), METAL, (0.75, 0.75, 0.78), 0.85, 0.85)
    # strip lights along the roof edge
    for sx in (-1, 1):
        kit.add_object(box((sx * (half - 0.06), belt + 0.38, side_z), (0.02, 0.012, z1 - z0 - 0.4), 0.0), SCREEN, (0.4, 0.3, 1.0), 0.9, 0.9)


def roll_cage_rear(kit, z, floor, top, half, colr):
    bulkhead(kit, z, floor, top, half, colr)


# --------------------------------------------------------------------------------------------------------- designs
GREY = (0.30, 0.30, 0.31)
DARK = (0.07, 0.07, 0.075)
BEIGE = (0.55, 0.50, 0.42)
TAN = (0.45, 0.28, 0.15)
CREAM = (0.74, 0.67, 0.55)
BURGUNDY = (0.30, 0.06, 0.06)
NAVY = (0.10, 0.12, 0.17)
CARPET_D = (0.06, 0.06, 0.06)
CARPET_B = (0.25, 0.21, 0.17)
WALNUT = (0.30, 0.15, 0.06)

DESIGNS = {
    #           seats style, seat colour, dash style, dash colour, wheel, carpet, extras, rows, trim
    'sedan':     ('cloth', GREY, 'classic', (0.09, 0.09, 0.095), 'classic', CARPET_D, [], 2, None),
    'wagon':     ('cloth', BEIGE, 'classic', (0.32, 0.28, 0.22), 'classic', CARPET_B, [], 2, (WOOD, WALNUT)),
    'hatch':     ('cloth', (0.18, 0.2, 0.25), 'classic', (0.06, 0.06, 0.065), 'sport', CARPET_D, [], 2, None),
    'compact':   ('cloth', (0.35, 0.33, 0.3), 'classic', (0.12, 0.12, 0.12), 'classic', CARPET_D, [], 2, None),
    'coupe':     ('leather', TAN, 'luxury', (0.05, 0.045, 0.04), 'luxury', CARPET_B, [], 2, (WOOD, WALNUT)),
    'muscle':    ('sport', (0.04, 0.04, 0.04), 'sport', (0.03, 0.03, 0.03), 'sport', CARPET_D, [], 2, (METAL, (0.55, 0.55, 0.57))),
    'limo':      ('leather', CREAM, 'luxury', (0.06, 0.05, 0.045), 'luxury', CARPET_B, ['limo'], 1, (WOOD, WALNUT)),
    'suv':       ('leather', (0.16, 0.1, 0.07), 'classic', (0.07, 0.065, 0.06), 'classic', CARPET_D, [], 2, (METAL, (0.4, 0.4, 0.42))),
    'pickup':    ('cloth', (0.24, 0.22, 0.2), 'utility', (0.1, 0.1, 0.1), 'utility', CARPET_D, ['rearwall'], 1, None),
    'taxi':      ('vinyl', (0.05, 0.05, 0.05), 'classic', (0.06, 0.06, 0.06), 'classic', CARPET_D, ['taxi'], 2, None),
    'police':    ('cloth', NAVY, 'classic', (0.05, 0.05, 0.055), 'police', CARPET_D, ['police'], 2, None),
    'police_suv': ('cloth', NAVY, 'classic', (0.05, 0.05, 0.055), 'police', CARPET_D, ['police'], 2, None),
    'van':       ('vinyl', (0.12, 0.12, 0.13), 'utility', (0.14, 0.14, 0.15), 'utility', (0.08, 0.08, 0.08), ['bulkhead'], 1, None),
    'ambulance': ('vinyl', (0.1, 0.14, 0.22), 'utility', (0.6, 0.6, 0.6), 'utility', (0.1, 0.1, 0.1), ['bulkhead'], 1, None),
    'boxtruck':  ('vinyl', (0.1, 0.1, 0.11), 'utility', (0.12, 0.12, 0.13), 'utility', (0.08, 0.08, 0.08), ['bulkhead'], 1, None),
    'firetruck': ('vinyl', (0.06, 0.06, 0.07), 'utility', (0.08, 0.08, 0.08), 'utility', (0.08, 0.08, 0.08), ['bulkhead'], 1, None),
}


def roof_at(prof, z):
    best = None
    for r in prof:
        if abs(r['z'] - z) < 0.051 and r['roof-0.4'] is not None:
            best = r['roof-0.4']
    return best


def build(model):
    c = CAB[model]
    gmin, gmax = c['glass_min'], c['glass_max']
    belt = gmin[1]
    top = gmax[1]
    ws_z = gmin[2]
    rear_z = gmax[2]
    walls = [w[2] for w in c['walls'] if w[2] is not None and w[2] > 0.5]
    half = (min(walls) if walls else 0.95) - 0.05
    floors = [r['floor+0.0'] for r in c['profile'] if r['floor+0.0'] is not None and ws_z < r['z'] < rear_z]
    floor = (min(floors) if floors else 0.3) + 0.08
    style, scol, dstyle, dcol, wheel, carpet, extras, rows, trim = DESIGNS[model]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    kit = Kit()
    # cab dimensions: for vans and trucks only the front glass belongs to the cab
    utility = 'bulkhead' in extras or 'rearwall' in extras
    seat_z = ws_z + 1.0 if not utility else ws_z + 0.95
    if model in ('boxtruck', 'firetruck'):
        seat_z = ws_z + 0.92
    cab_end = seat_z + 0.5 if utility else (rear_z - 0.05)
    if model == 'pickup':
        cab_end = rear_z - 0.02
    dashboard(kit, ws_z, belt, half, floor, dstyle, dcol, trim)
    steering(kit, ws_z, belt, wheel, dcol if wheel != 'police' else (0.04, 0.04, 0.04))
    sw = 0.5 if half > 0.85 else 0.46
    seat(kit, -0.4, seat_z, floor, style, scol, sw)
    seat(kit, 0.4, seat_z, floor, style, scol, sw)
    if not utility:
        console(kit, ws_z, floor, belt, seat_z - ws_z - 0.1, dcol, dstyle)
    else:
        # engine cover / flat console between utility seats
        kit.add_object(box((0, floor + 0.13, seat_z - 0.25), (0.3, 0.26, 0.6), 0.03, 2), PLASTIC, dcol, 0.5, 0.3)
    door_cards(kit, ws_z + 0.25, cab_end, floor, belt, half + 0.02, dcol,
               scol if style != 'leather' else scol, LEATHER if style == 'leather' else (VINYL if style == 'vinyl' else CLOTH))
    floor_carpet(kit, ws_z + 0.3, cab_end, floor - 0.01, half, carpet)
    if rows >= 2 and not utility:
        rz = seat_z + 0.86
        if model in ('coupe', 'muscle'):
            rz = seat_z + 0.78
        bench(kit, rz, floor, half, style if style != 'sport' else 'leather', scol)
        # parcel shelf behind the rear seat up to the rear window
        shelf_z0 = rz + 0.5
        if shelf_z0 < rear_z:
            kit.add_object(box((0, belt - 0.01, (shelf_z0 + rear_z) * 0.5), (half * 2 - 0.04, 0.02, rear_z - shelf_z0 + 0.05), 0.0, 1, 0, None, False),
                           CARPET, carpet, 0.5, 0.5)
    if 'police' in extras:
        police_cage(kit, seat_z + 0.42, floor, top - 0.02, half)
        laptop(kit, ws_z, belt)
    if 'taxi' in extras:
        taxi_partition(kit, seat_z + 0.42, floor, belt, top - 0.02, half)
        taxi_meter(kit, ws_z, belt)
    if 'limo' in extras:
        kit.add_object(box((0, (floor + top) * 0.5, seat_z + 0.45), (half * 2 - 0.04, top - floor - 0.03, 0.05), 0.01), WOOD, WALNUT, 0.6, 0.4)
        limo_lounge(kit, seat_z + 0.55, rear_z + 0.6, floor, belt, half, CREAM, WALNUT)
    if 'bulkhead' in extras:
        bulkhead(kit, seat_z + 0.5, floor, top + 0.05, half, (0.18, 0.18, 0.19))
    if 'rearwall' in extras:
        bulkhead(kit, rear_z + 0.02, floor, belt, half, dcol)
    ob = kit.finish(model + '_interior')
    os.makedirs(OUT, exist_ok=True)
    for o in bpy.context.scene.objects:
        o.select_set(o == ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, model + '.glb'), use_selection=True, export_format='GLB',
                              export_texcoords=True, export_normals=True, export_vertex_color='ACTIVE',
                              export_all_vertex_colors=True, export_materials='NONE', export_yup=True)
    print('OK', model, len(ob.data.polygons), 'faces')


if __name__ == '__main__':
    models = sys.argv[1:] or sorted(DESIGNS)
    for m in models:
        build(m)
