"""Vaynara's outfit as separate garments (run: python3 tools/blender/vaynara_outfit.py).

Input: the character exported from Godot (tools/export_character_glb.gd -> /home/claude/work/vay/vaynara.glb).
Output: /home/claude/work/vay/vaynara_outfit.glb with the new skinned meshes; tools/build_vaynara.gd swaps them
into assets/models/characters/vaynara.scn on the original skeleton.

Look (owner's reference): blonde bob, dark grey zip hoodie worn open and loose, red crop top showing the midriff,
slim dark jeans with waistband, loops, button and back pockets, tall black lace-up boots with two buckled straps.
Every piece is its own mesh: Torso (skin of the midriff and chest, joined to the neck), CropTop, Hoodie, Hood,
Strings, Zipper, Jeans, Boots and Metal (button, rivets, aglets, eyelets, buckles).

Blender space: z up, the character faces -y, its left side is +x, T-pose arms along x at z 1.418.
Vertex data for shaders/garment.gdshader: UV in metres (tiling fabric), COLOR.rgb shade (seams, folds, inner
side), COLOR.a = 1 on ribbed knit (hems, cuffs). Skin weights are copied from the nearest old garment vertices.
"""
import bpy, bmesh, math, os
from mathutils import Vector
from mathutils.kdtree import KDTree
from mathutils.bvhtree import BVHTree

SRC = '/home/claude/work/vay/vaynara.glb'
OUT = '/home/claude/work/vay/vaynara_outfit.glb'
TAU = math.tau


def smooth(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def table_at(table, z):
    """Catmull-Rom through rows (z, v1, v2, ...)."""
    zs = [r[0] for r in table]
    if z <= zs[0]:
        return list(table[0][1:])
    if z >= zs[-1]:
        return list(table[-1][1:])
    i = max(k for k in range(len(zs) - 1) if zs[k] <= z)
    t = (z - zs[i]) / (zs[i + 1] - zs[i])
    p0, p1, p2, p3 = table[max(i - 1, 0)][1:], table[i][1:], table[i + 1][1:], table[min(i + 2, len(table) - 1)][1:]
    return [0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (-a + 3 * b - 3 * c + d) * t ** 3)
            for a, b, c, d in zip(p0, p1, p2, p3)]


# ------------------------------------------------------------------------------------------------- the body
# skin torso: z, half width, front depth, back depth (from the spine line), spine y
BODY = [
    (0.78, 0.182, 0.090, 0.128, 0.030),
    (0.84, 0.186, 0.094, 0.142, 0.026),
    (0.90, 0.180, 0.098, 0.140, 0.022),
    (0.95, 0.170, 0.104, 0.124, 0.018),
    (1.00, 0.156, 0.110, 0.104, 0.012),
    (1.04, 0.140, 0.112, 0.088, 0.008),
    (1.08, 0.125, 0.110, 0.078, 0.004),
    (1.12, 0.116, 0.106, 0.074, 0.002),
    (1.16, 0.113, 0.104, 0.075, 0.001),
    (1.20, 0.118, 0.106, 0.080, 0.001),
    (1.24, 0.130, 0.110, 0.092, 0.002),
    (1.28, 0.140, 0.114, 0.104, 0.004),
    (1.32, 0.146, 0.114, 0.112, 0.006),
    (1.36, 0.150, 0.104, 0.116, 0.010),
    (1.40, 0.152, 0.086, 0.114, 0.016),
    (1.44, 0.140, 0.062, 0.104, 0.024),
    (1.48, 0.100, 0.040, 0.090, 0.034),
]
EXP = 2.3
BUST_Z, BUST_X, BUST_A = 1.300, 0.084, 0.027


def section(theta, w, F, B, yc, n=EXP):
    s, c = math.sin(theta), math.cos(theta)
    x = w * math.copysign(abs(s) ** (2 / n), s)
    y = yc - F * abs(c) ** (2 / n) if c >= 0 else yc + B * abs(c) ** (2 / n)
    return x, y


def bust(x, z, bridge=False):
    """Forward bulge of the bust (front surface). bridge: fabric spans the cleavage instead of following it."""
    ax = abs(x)
    if bridge and ax < BUST_X:
        ax = BUST_X
    sz = 0.048 if z > BUST_Z else 0.034
    return BUST_A * math.exp(-((ax - BUST_X) / 0.052) ** 2 - ((z - BUST_Z) / sz) ** 2)


def body_point(theta, z, off=0.0, bridge=False, drape=0.0):
    """Skin (off 0) or a layer off metres above it. drape > 0: below the bust the front falls straight instead of
    following the waist in (garments hang from the bust)."""
    w, F, B, yc = table_at(BODY, z)
    x, y = section(theta, w + off, F + off, B + off, yc)
    c = math.cos(theta)
    if c > 0:
        k = c ** 0.6
        y -= bust(x, z, bridge) * k
        if drape > 0 and z < BUST_Z:
            # the front hangs from the bust apex: never closer to the spine than a line falling from it
            wa, Fa, Ba, yca = table_at(BODY, BUST_Z)
            apex = yca - Fa - BUST_A - off
            fall = apex + (BUST_Z - z) * drape
            y = min(y, lerp(y, fall, k * smooth(BUST_X + 0.06, 0.0, abs(x)) ** 0.5))
        # navel
        y += 0.0055 * math.exp(-(x / 0.0085) ** 2 - ((z - 1.072) / 0.011) ** 2) * (1.0 if off < 0.002 else 0.0)
    return Vector((x, y, z))


# ------------------------------------------------------------------------------------------------- mesh helper
class MB:
    """Mesh builder: vertices with colour, faces with per-corner UVs."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.col = self.bm.verts.layers.float_color.new('col')
        self.uvl = self.bm.loops.layers.uv.new('UVMap')

    def v(self, p, col=(1, 1, 1, 0)):
        vv = self.bm.verts.new(p)
        vv[self.col] = col
        return vv

    def f(self, vs, uvs):
        try:
            face = self.bm.faces.new(vs)
        except ValueError:
            return None
        for lp, uv in zip(face.loops, uvs):
            lp[self.uvl].uv = uv
        face.smooth = True
        return face

    def grid(self, P, C=None, U=None, closed=False, flip=False):
        """P[i][j] points (rings i, columns j). closed: column j wraps. U[i][j]: uv; C[i][j]: colour."""
        R = len(P)
        Cn = len(P[0])
        V = [[self.v(P[i][j], C[i][j] if C else (1, 1, 1, 0)) for j in range(Cn)] for i in range(R)]
        for i in range(R - 1):
            for j in range(Cn if closed else Cn - 1):
                j1 = (j + 1) % Cn
                q = [V[i][j], V[i][j1], V[i + 1][j1], V[i + 1][j]]
                uv = [U[i][j], U[i][j + 1] if U and j + 1 < len(U[i]) else (U[i][j1] if U else (0, 0)),
                      U[i + 1][j + 1] if U and j + 1 < len(U[i + 1]) else (U[i + 1][j1] if U else (0, 0)), U[i + 1][j]] if U else [(0, 0)] * 4
                if flip:
                    q.reverse(); uv.reverse()
                self.f(q, uv)
        return V

    def tube(self, path, radii, seg=10, col=(1, 1, 1, 0), caps=False, up=Vector((0, 0, 1))):
        """Tube along path points with radius per point (or (rx, ry))."""
        rings = []
        for k, p in enumerate(path):
            t = (path[min(k + 1, len(path) - 1)] - path[max(k - 1, 0)]).normalized()
            a = up.cross(t)
            if a.length < 1e-4:
                a = Vector((1, 0, 0)).cross(t)
            a.normalize()
            b = t.cross(a).normalized()
            r = radii[k] if isinstance(radii, (list, tuple)) else radii
            rx, ry = (r, r) if not isinstance(r, (list, tuple)) else r
            rings.append([p + a * math.cos(TAU * j / seg) * rx + b * math.sin(TAU * j / seg) * ry for j in range(seg)])
        L = 0.0
        U = []
        for k in range(len(path)):
            if k:
                L += (path[k] - path[k - 1]).length
            U.append([(j / seg * 0.05, L) for j in range(seg + 1)])
        V = self.grid(rings, [[col] * seg for _ in rings], U, closed=True)
        if caps:
            for ring, rev in ((V[0], True), (V[-1], False)):
                vs = list(reversed(ring)) if rev else list(ring)
                self.f(vs, [(0, 0)] * len(vs))
        return V

    def box(self, centre, ax, ay, az, col=(1, 1, 1, 0)):
        """Box from a centre and three half-axis vectors."""
        c = Vector(centre)
        pts = [c + ax * sx + ay * sy + az * sz for sz in (-1, 1) for sy in (-1, 1) for sx in (-1, 1)]
        V = [self.v(p, col) for p in pts]
        for q in ((0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)):
            self.f([V[i] for i in q], [(0, 0), (0.02, 0), (0.02, 0.02), (0, 0.02)])

    def obj(self, material):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces[:])
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        # vertex colour as a real colour attribute (exported as COLOR_0)
        attr = me.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
        cl = self.bm.verts.layers.float_color['col']
        for i, v in enumerate(self.bm.verts):
            attr.data[i].color = v[cl]
        me.color_attributes.active_color = attr
        mat = bpy.data.materials.get(material) or bpy.data.materials.new(material)
        me.materials.append(mat)
        return ob


def outward_normals_ok(ob, centre_fn):
    """Faces of an open garment point away from the body axis (recalc may pick either side of an open sheet)."""
    me = ob.data
    flip = 0
    for p in me.polygons:
        c = p.center
        if p.normal.dot(c - centre_fn(c)) < 0:
            flip += 1
    if flip > len(me.polygons) / 2:
        for p in me.polygons:
            p.flip()
        me.update()


def axis_torso(c):
    return Vector((0.0, table_at(BODY, c.z)[3], c.z))


# ------------------------------------------------------------------------------------------------- load the old model
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
ARM = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
OLD = {o.name: o for o in bpy.context.scene.objects if o.type == 'MESH'}
for _n, _o in OLD.items():
    _o.name = 'OLD_' + _n          # free the names for the new garments
BONES = {b.name: (ARM.matrix_world @ b.head_local, ARM.matrix_world @ b.tail_local) for b in ARM.data.bones}

# the neck opening of the Body mesh: the torso skin joins it exactly
_bmn = bmesh.new()
_bmn.from_mesh(OLD['Body'].data)
NECK = sorted({v.index: v.co.copy() for e in _bmn.edges if e.is_boundary for v in e.verts if abs(v.co.x) < 0.2}.values(),
              key=lambda p: math.atan2(p.x, -(p.y - 0.042)))
NECK_C = Vector((0.0, 0.042, 0.0))


def neck_at(theta):
    """Point of the neck opening at angle theta around the neck axis (0 front, +pi/2 left)."""
    best = None
    for k in range(len(NECK)):
        a = math.atan2(NECK[k].x, -(NECK[k].y - NECK_C.y))
        d = abs((a - theta + math.pi) % TAU - math.pi)
        if best is None or d < best[0]:
            best = (d, k)
    # interpolate between the two neighbours
    k = best[1]
    p = NECK[k]
    a = math.atan2(p.x, -(p.y - NECK_C.y))
    k2 = (k + (1 if ((theta - a + math.pi) % TAU - math.pi) > 0 else -1)) % len(NECK)
    q = NECK[k2]
    a2 = math.atan2(q.x, -(q.y - NECK_C.y))
    span = (a2 - a + math.pi) % TAU - math.pi
    t = 0.0 if abs(span) < 1e-6 else min(max(((theta - a + math.pi) % TAU - math.pi) / span, 0.0), 1.0)
    return p.lerp(q, t)


def neck_s(theta):
    """The neck opening smoothed over +-25 degrees (its real edge zigzags; it used to hide under a collar)."""
    acc = Vector((0, 0, 0))
    n = 9
    for k in range(n):
        acc += neck_at(theta + math.radians(-25 + 50 * k / (n - 1)))
    p = acc / n
    # keep the radius of the real edge at this angle, only the height is averaged
    r = neck_at(theta)
    return Vector((r.x, r.y, p.z))


SEG = 56   # columns around the torso


def theta_of(j, n=SEG):
    return TAU * j / n


def radial(p, cy=None):
    d = p - Vector((0.0, NECK_C.y if cy is None else cy, p.z))
    d.z = 0
    return d.normalized() if d.length > 1e-6 else Vector((0, -1, 0))


def upper(th, b, off=0.0):
    """Upper torso between the 1.43 m ring (b = 0) and the neck opening (b = 1), lifted off metres."""
    p0 = body_point(th, 1.43)
    tt = th if th <= math.pi else th - TAU
    n = neck_at(tt) if b >= 0.999 else neck_s(tt)
    p = p0.lerp(n, smooth(0.0, 1.0, b))
    return p + radial(p) * off + Vector((0, 0, off * 0.6 * b))


# ------------------------------------------------------------------------------------------------- torso skin
def build_torso():
    mb = MB('Torso')
    zs = [0.93 + 0.02 * i for i in range(26)]   # 0.93 .. 1.43
    P, U, C = [], [], []
    for z in zs:
        P.append([body_point(theta_of(j), z) for j in range(SEG)])
    # up to the neck opening
    for k in range(1, 7):
        P.append([upper(theta_of(j), k / 6) for j in range(SEG)])
    for i, row in enumerate(P):
        U.append([((j - SEG / 2) / SEG * 0.72, row[0].z) for j in range(SEG + 1)])
        C.append([(1, 1, 1, 0)] * SEG)
    mb.grid(P, C, U, closed=True)
    return mb.obj('skin_flat')


# ------------------------------------------------------------------------------------------------- crop top
CROP_HEM = 1.168


def build_crop():
    mb = MB('CropTop')
    OFF = 0.0045
    P, U, C = [], [], []
    zs = [CROP_HEM + 0.016 * i for i in range(17)] + [1.43]
    for i, z in enumerate(zs):
        row = []
        for j in range(SEG):
            th = theta_of(j)
            p = body_point(th, z, OFF, bridge=True, drape=0.18)
            row.append(p)
        P.append(row)
    # crew neck: rises to a ribbed band 3.5 cm below the neck opening at the front, close to it at the back
    # crew neck: the top follows the upper torso up to a scooped neckline (low at the front, close at the back)
    for k in range(1, 6):
        row = []
        for j in range(SEG):
            th = theta_of(j)
            front = max(math.cos(th), 0.0)
            bmax = 0.9 - 0.5 * front ** 1.4
            row.append(upper(th, k / 5 * bmax, OFF + 0.0015 * (k / 5)))
        P.append(row)
    for i, row in enumerate(P):
        U.append([((j - SEG / 2) / SEG * 0.8, i * 0.016) for j in range(SEG + 1)])
        rib = 1.0 if i >= len(P) - 2 else 0.0
        # soft folds of the knit under the bust, stretched smooth over it; shadowed in the armpits (where it can
        # show between the sleeve and the hoodie body when the arms are down)
        cr = []
        for j in range(SEG):
            th = theta_of(j)
            pit = smooth(0.55, 0.85, abs(math.sin(th))) * smooth(1.22, 1.32, row[j].z)
            sh = (0.94 + 0.06 * math.cos(th * 14 + i)) * (1 - 0.8 * pit)
            cr.append((sh, sh, sh, rib))
        C.append(cr)
    V = mb.grid(P, C, U, closed=True)
    # rolled hem: turn the bottom edge under by 8 mm so the top has a visible thickness
    hem = []
    for j in range(SEG):
        p = V[0][j].co
        d = (p - axis_torso(p))
        d.z = 0
        d.normalize()
        hem.append(p - d * 0.004 + Vector((0, 0, 0.008)))
    Vin = [mb.v(h, (0.55, 0.55, 0.55, 0)) for h in hem]
    for j in range(SEG):
        j1 = (j + 1) % SEG
        mb.f([V[0][j1], V[0][j], Vin[j], Vin[j1]], [(0, 0), (0.01, 0), (0.01, 0.01), (0, 0.01)])
    ob = mb.obj('crop')
    return ob


# ------------------------------------------------------------------------------------------------- hoodie
HEM = 0.865
HOOD_OFF = [  # z, extra width, extra front, extra back (over the skin)
    (0.86, 0.022, 0.030, 0.026), (0.95, 0.024, 0.032, 0.030), (1.05, 0.034, 0.030, 0.036), (1.15, 0.046, 0.028, 0.038),
    (1.25, 0.042, 0.030, 0.032), (1.32, 0.040, 0.026, 0.026), (1.40, 0.044, 0.024, 0.024), (1.46, 0.036, 0.024, 0.026)]
OPEN = [(0.86, 0.118), (1.00, 0.112), (1.16, 0.104), (1.28, 0.094), (1.38, 0.078), (1.46, 0.060), (1.51, 0.050)]


def hood_point(t, z, extra=0.0):
    """t in [0, 1] runs around the hoodie from the left front edge, over the back, to the right front edge."""
    xo = table_at(OPEN, z)[0]
    w, F, B, yc = table_at(BODY, z)
    ew, ef, eb = table_at(HOOD_OFF, z)
    # the angle of the front edge on this ring
    W = w + ew + extra
    so = min((xo / W) ** (EXP / 2), 0.999)
    th0 = math.asin(so)
    th = th0 + t * (TAU - 2 * th0)
    x, y = section(th, W, F + ef + extra, B + eb + extra, yc)
    c = math.cos(th)
    if c > 0:
        # front panels: hang straight from the bust down (loose), a little forward of the crop top
        wa, Fa, Ba, yca = table_at(BODY, BUST_Z)
        apex = yca - Fa - BUST_A - 0.03 - extra
        yb = y - bust(x, z, True) * c ** 0.6
        if z < BUST_Z:
            fall = apex + (BUST_Z - z) * 0.06
            yb = min(yb, lerp(yb, fall, smooth(0.25, 0.9, c)))
        y = yb
        # the open edges roll forward and outward a touch
        edge = smooth(0.06, 0.0, min(t, 1 - t))
        y -= 0.008 * edge
    return Vector((x, y, z)), th


def build_hoodie():
    mb = MB('Hoodie')
    NT = 64
    zs = [HEM + 0.015 * i for i in range(5)] + [HEM + 0.06 + 0.03 * i for i in range(17)] + [1.43 + 0.01 * k for k in range(1, 6)]
    P, U, C = [], [], []
    for i, z in enumerate(zs):
        row, cr = [], []
        for j in range(NT + 1):
            t = j / NT
            if z <= 1.43 + 1e-6:
                p, th = hood_point(t, z)
            else:
                # yoke: from the 1.43 ring over the shoulders to the collar round the neck
                b = (z - 1.43) / 0.05
                p0, th = hood_point(t, 1.43)
                n = neck_s(th if th <= math.pi else th - TAU)
                tgt = n + radial(n) * 0.026
                tgt.z = n.z - 0.012
                p = p0.lerp(tgt, smooth(0.0, 1.0, b))
                p.z += 0.016 * math.sin(math.pi * b) * abs(math.sin(th)) ** 0.5
            if z < HEM + 0.07 and z <= 1.43:
                # ribbed hem band: gathers in a little
                p = axis_torso(p) + (p - axis_torso(p)) * (0.985 if z < HEM + 0.055 else 1.0)
            # loose folds: low-frequency waves around, stronger at the sides and lower back
            side = abs(math.sin(th))
            fold = 0.004 * math.sin(th * 9 + z * 23) * (0.4 + side) * smooth(1.40, 1.05, z)
            d = p - axis_torso(p); d.z = 0
            if d.length > 0:
                p = p + d.normalized() * fold
            row.append(p)
            shade = 0.9 + 9.0 * fold
            rib = 1.0 if z < HEM + 0.055 else 0.0
            cr.append((shade, shade, shade, rib))
        P.append(row)
        C.append(cr)
        U.append([(j / NT * 1.05, z) for j in range(NT + 1)])
    V = mb.grid(P, C, U, closed=False)
    ob = mb.obj('hoodie')
    outward_normals_ok(ob, axis_torso)
    return ob, P


def sleeve_path(side):
    s = 1 if side == 'l' else -1
    pts = []
    for k in range(23):
        x = 0.115 + k * (0.628 - 0.115) / 22
        pts.append(Vector((s * x, 0.054, 1.418 - 0.016 * smooth(0.26, 0.12, x))))
    return pts


SLEEVE_R = [  # x along the arm, radius front-back (y), radius up-down (z)
    (0.115, 0.064, 0.056), (0.16, 0.066, 0.059), (0.22, 0.066, 0.061), (0.30, 0.064, 0.060), (0.39, 0.060, 0.057),
    (0.46, 0.058, 0.054), (0.53, 0.055, 0.051), (0.575, 0.052, 0.049), (0.585, 0.040, 0.038), (0.628, 0.036, 0.034)]


def build_sleeves():
    mb = MB('Sleeves')
    SEGS = 20
    for side in ('l', 'r'):
        s = 1 if side == 'l' else -1
        path = sleeve_path(side)
        rings, C, U = [], [], []
        for k, p in enumerate(path):
            x = abs(p.x)
            ry, rz = table_at(SLEEVE_R, x)
            # bunched fabric on the forearm above the cuff
            bunch = 0.0035 * math.sin(x * 95) * smooth(0.40, 0.55, x) * smooth(0.585, 0.57, x)
            ring, cr = [], []
            for j in range(SEGS):
                a = TAU * j / SEGS
                q = Vector((p.x, p.y + math.cos(a) * (ry + bunch), p.z + math.sin(a) * (rz + bunch * 0.7)))
                ring.append(q)
                rib = 1.0 if x > 0.582 else 0.0
                sh = 0.92 + 18.0 * bunch * math.cos(a * 2 + x * 40)
                cr.append((sh, sh, sh, rib))
            if s < 0:
                ring.reverse(); cr.reverse()
            rings.append(ring)
            C.append(cr)
            U.append([(j / SEGS * 0.38, x) for j in range(SEGS + 1)])
        mb.grid(rings, C, U, closed=True)
    ob = mb.obj('hoodie')
    outward_normals_ok(ob, lambda c: Vector((c.x, 0.054, 1.418)))
    return ob


def build_hood():
    """The hood lying down on the upper back, and its rim standing round the neck as a collar."""
    mb = MB('Hood')
    NU, NV = 20, 12
    P, C, U = [], [], []
    for i in range(NV + 1):
        v = i / NV
        row, cr = [], []
        for j in range(NU + 1):
            u = j / NU * 2 - 1           # -1 right .. 1 left
            th = math.pi - u * 1.25
            n = neck_s(th if th <= math.pi else th - TAU)
            a = n + radial(n) * 0.03
            a.z = n.z - 0.004
            # bottom of the hood: a rounded U low between the shoulder blades
            zb = 1.335 + 0.06 * u * u
            w, F, B, yc = table_at(BODY, zb)
            bot = Vector((u * 0.105, yc + B + table_at(HOOD_OFF, zb)[2] + 0.004, zb))
            # in between it lies on the back, puffed out where the empty hood folds
            zm = lerp(a.z, bot.z, v)
            w, F, B, yc = table_at(BODY, zm)
            back = yc + B + table_at(HOOD_OFF, zm)[2] + 0.004
            p = a.lerp(bot, smooth(0.0, 1.0, v) * 0.35 + v * 0.65)
            p.y = max(p.y, back) + 0.026 * math.sin(math.pi * v) * (1 - 0.5 * u * u) + 0.004 * math.sin(u * 6 + v * 4)
            row.append(p)
            sh = 0.8 + 0.2 * math.sin(math.pi * v)
            cr.append((sh, sh, sh, 0))
        P.append(row)
        C.append(cr)
        U.append([((j / NU) * 0.5, v * 0.3) for j in range(NU + 1)])
    mb.grid(P, C, U)
    # collar: the hood's opening rim, a band standing round the neck from one front edge to the other
    NC = 40
    band = []
    for k in range(2):
        row = []
        for j in range(NC + 1):
            t = j / NC
            xo = table_at(OPEN, 1.49)[0]
            th0 = math.asin(min((xo / 0.12) ** (EXP / 2), 0.99))
            th = th0 + t * (TAU - 2 * th0)
            n = neck_s(th if th <= math.pi else th - TAU)
            d = (n - Vector((0, NECK_C.y, n.z)))
            d.z = 0
            d.normalize()
            r = 0.022 + 0.012 * k + 0.012 * max(-math.cos(th), 0)
            p = n + d * r
            p.z = n.z - 0.03 + 0.045 * k + 0.02 * max(-math.cos(th), 0) * k
            row.append(p)
        band.append(row)
    mb.grid(band, [[(0.85, 0.85, 0.85, 1.0)] * (NC + 1)] * 2, [[(j / NC * 0.5, k * 0.05) for j in range(NC + 1)] for k in range(2)])
    ob = mb.obj('hoodie')
    outward_normals_ok(ob, lambda c: Vector((0, 0.03, c.z)))
    return ob


def build_zipper(hood_rows):
    """Zip tapes with teeth along both open edges (UV.y runs along the zip for the teeth pattern)."""
    mb = MB('Zipper')
    for side, j in (('l', 0), ('r', -1)):
        rows = []
        U = []
        L = 0.0
        prev = None
        for i, row in enumerate(hood_rows):
            p = row[j]
            q = row[1 if j == 0 else -2]
            inward = (q - p).normalized()
            out = (p - axis_torso(p)); out.z = 0; out.normalize()
            a = p + out * 0.0025 - inward * 0.003
            b = p + out * 0.0025 + inward * 0.009
            if prev is not None:
                L += (p - prev).length
            prev = p
            rows.append([a, b])
            U.append([(0, L), (1, L)])
        mb.grid(rows, None, U)
    ob = mb.obj('zipper')
    outward_normals_ok(ob, axis_torso)
    return ob


def build_strings(metal):
    mb = MB('Strings')
    for s in (1, -1):
        top = neck_s(0.55 * s)
        path = []
        for k in range(14):
            t = k / 13
            z = top.z - 0.035 - t * 0.21
            x = s * (0.042 + 0.012 * t)
            y = body_point(0.35 * s, z, 0.03, bridge=True).y - 0.004 + 0.006 * math.sin(t * 3)
            path.append(Vector((x, y, z)))
        mb.tube(path, 0.0035, 6, (0.82, 0.82, 0.82, 0))
        end = path[-1]
        metal.tube([end + Vector((0, 0, 0.004)), end - Vector((0, 0, 0.022))], 0.0042, 6, (0.75, 0.75, 0.75, 0), caps=True)
    ob = mb.obj('string')
    return ob


def build_pockets(hood_rows):
    """Split kangaroo pockets on the front panels: a patch a few mm proud with a slanted side opening."""
    mb = MB('Pockets')
    NT = len(hood_rows[0]) - 1
    zs_idx = [i for i, row in enumerate(hood_rows) if 0.905 <= row[0].z <= 1.07]
    for side in (0, 1):
        P, C, U = [], [], []
        for i in zs_idx:
            row = hood_rows[i]
            z = row[0].z
            # columns from the zip edge to the slanted opening
            k_end = 0.14 + (z - 0.905) / (1.07 - 0.905) * (-0.05)   # fraction of the way to the side seam
            cols = []
            for c in range(8):
                f = 0.012 + c / 7 * (0.19 + k_end - 0.012) * 0.6
                t = f if side == 0 else 1 - f
                jj = t * NT
                j0 = int(min(jj, NT - 1))
                p = hood_rows[i][j0].lerp(hood_rows[i][j0 + 1], jj - j0)
                out = (p - axis_torso(p)); out.z = 0; out.normalize()
                cols.append(p + out * 0.0045)
            if side == 1:
                cols.reverse()
            P.append(cols)
            C.append([(0.88, 0.88, 0.88, 0)] * len(cols))
            U.append([(c * 0.02, z) for c in range(len(cols) + 1)])
        mb.grid(P, C, U)
    ob = mb.obj('hoodie')
    outward_normals_ok(ob, axis_torso)
    return ob


# ------------------------------------------------------------------------------------------------- jeans
WAIST = 0.985
CROTCH = 0.815
LEG = sorted([  # z, side radius, front-back radius (rows must be in rising z for table_at)
    (0.80, 0.090, 0.094), (0.74, 0.081, 0.086), (0.68, 0.074, 0.079), (0.62, 0.067, 0.071), (0.56, 0.060, 0.063),
    (0.52, 0.057, 0.060), (0.47, 0.055, 0.060), (0.42, 0.056, 0.062), (0.36, 0.052, 0.057), (0.29, 0.047, 0.051)])


def leg_axis(z, s):
    th0, th1 = BONES['thigh_l']
    c0, c1 = BONES['calf_l']
    if z >= th1.z:
        t = (z - th1.z) / (th0.z - th1.z)
        p = th1.lerp(th0, t)
    else:
        t = (z - c1.z) / (c0.z - c1.z)
        p = c1.lerp(c0, t)
    return Vector((p.x * s, p.y, z))


def jeans_ring(z, off=0.0):
    w, F, B, yc = table_at(BODY, z)
    pts = []
    for j in range(48):
        th = TAU * j / 48
        x, y = section(th, w + 0.008 + off, F + 0.007 + off, B + 0.009 + off, yc)
        pts.append(Vector((x, y, z)))
    return pts


def build_jeans(metal):
    mb = MB('Jeans')
    # hips: waist down to the crotch
    zs = [WAIST - 0.017 * i for i in range(11)]
    P = [jeans_ring(z) for z in zs]
    # waistband stands 2 mm proud
    for i in range(3):
        P[i] = jeans_ring(zs[i], 0.0025)
    C = [[(0.8 if i < 3 else 1.0,) * 3 + (0,) for j in range(48)] for i in range(len(P))]
    # front pocket openings and the fly as darker seams
    for i, z in enumerate(zs):
        for j in range(48):
            th = TAU * j / 48
            x = P[i][j].x
            front = math.cos(th) > 0.3
            pocket = abs(abs(x) - (0.085 + (WAIST - z) * 0.9)) < 0.006 and z > WAIST - 0.09 and front
            fly = abs(x - 0.022) < 0.005 and z > WAIST - 0.13 and front and i > 2
            if pocket or fly:
                c = C[i][j]
                C[i][j] = (c[0] * 0.55, c[1] * 0.55, c[2] * 0.55, 0)
    U = [[((j - 24) / 48 * 0.8, z) for j in range(49)] for z in zs]
    V = mb.grid(P, C, U, closed=True)
    ring = V[-1]
    # legs: the hip ring splits into two leg loops through an inner seam under the crotch
    for s in (1, -1):
        idx = list(range(0, 25)) if s > 0 else [0] + list(range(47, 23, -1))
        loop = [ring[k].co.copy() for k in idx]
        fb, ff = loop[-1], loop[0]
        seam = []
        for q in range(1, 8):
            t = q / 8
            p = fb.lerp(ff, t)
            seam.append(Vector((0.002 * s, p.y, CROTCH - 0.045 * math.sin(math.pi * t))))
        loopv = [ring[k] for k in idx] + [mb.v(p) for p in seam]
        n = len(loopv)
        # leg rings, angles matched to the loop: 25 on the outer half, 7 on the inner side
        rows = [loopv]
        zs_leg = [0.80 - 0.03 * k for k in range(18)]
        for z in zs_leg:
            ax = leg_axis(z, s)
            rx, ry = table_at(LEG, z)
            row = []
            for q in range(n):
                phi = math.pi * q / 24 if q <= 24 else math.pi + math.pi * (q - 24) / 8
                p = ax + Vector((s * math.sin(phi) * rx, -math.cos(phi) * ry, 0))
                # knee and thigh wrinkles: slight waves
                wr = 0.0022 * math.sin(phi * 3 + z * 60) * smooth(0.6, 0.5, z) * smooth(0.35, 0.45, z)
                p += Vector((s * math.sin(phi), -math.cos(phi), 0)) * wr
                b = smooth(CROTCH, CROTCH - 0.10, z)
                if b < 1:
                    p = loopv[q].co.lerp(p, b) if q < len(loopv) else p
                    p.z = lerp(loopv[q].co.z, z, b) if b < 1 else z
                row.append(mb.v(p, (1, 1, 1, 0)))
            rows.append(row)
        L = 0.0
        for i in range(len(rows) - 1):
            for q in range(n):
                q1 = (q + 1) % n
                a, b_, c, d = rows[i][q], rows[i][q1], rows[i + 1][q1], rows[i + 1][q]
                quad = [a, b_, c, d] if s > 0 else [b_, a, d, c]
                u0, u1 = q / n * 0.55, (q + 1) / n * 0.55
                uv = [(u0, a.co.z), (u1, b_.co.z), (u1, c.co.z), (u0, d.co.z)] if s > 0 else [(u1, b_.co.z), (u0, a.co.z), (u0, d.co.z), (u1, c.co.z)]
                mb.f(quad, uv)
        # outer side seam: darker line on the outer side of the leg
        for row in rows[1:]:
            vv = row[12]
            vv[mb.col] = (0.7, 0.7, 0.7, 0)
    # belt loops (5) and back pockets
    for th in (0.62, 1.45, math.pi, TAU - 1.45, TAU - 0.62):
        x, y = section(th, table_at(BODY, 0.965)[0] + 0.012, table_at(BODY, 0.965)[1] + 0.011, table_at(BODY, 0.965)[2] + 0.013, table_at(BODY, 0.965)[3])
        out = Vector((math.sin(th), -math.cos(th), 0)).normalized()
        tang = Vector((0, 0, 1)).cross(out).normalized()
        mb.box((x, y, 0.963), tang * 0.006, out * 0.002, Vector((0, 0, 0.022)), (0.8, 0.8, 0.8, 0))
    for s in (1, -1):
        P2, C2, U2 = [], [], []
        for zi in range(6):
            z = 0.928 - zi * 0.022
            row = []
            for k in range(6):
                th = math.pi - s * (0.25 + k * 0.12)
                w, F, B, yc = table_at(BODY, z)
                x, y = section(th, w + 0.0115, F + 0.0105, B + 0.0125, yc)
                row.append(Vector((x, y, z)))
            if s < 0:
                row.reverse()
            P2.append(row)
            C2.append([(0.85, 0.85, 0.85, 0)] * 6)
            U2.append([(k * 0.025, z) for k in range(7)])
        mb.grid(P2, C2, U2)
    # metal: button and rivets
    w, F, B, yc = table_at(BODY, 0.965)
    metal.tube([Vector((0, yc - F - 0.0125, 0.965)), Vector((0, yc - F - 0.017, 0.965))], 0.0075, 10, (0.8, 0.72, 0.5, 0), caps=True,
               up=Vector((0, 0, 1)))
    for s in (1, -1):
        x, y = section(0.75 * s, w + 0.011, F + 0.01, B, yc)
        metal.tube([Vector((x, y, 0.95)), Vector((x, y - 0.003, 0.95))], 0.0028, 6, (0.8, 0.72, 0.5, 0), caps=True)
    ob = mb.obj('denim')
    outward_normals_ok(ob, lambda c: leg_axis(c.z, 1 if c.x > 0 else -1) if c.z < CROTCH else axis_torso(c))
    return ob


# ------------------------------------------------------------------------------------------------- boots
SHAFT_TOP = 0.375
SHAFT = [  # z, side radius, front-back radius (over the jeans)
    (0.10, 0.056, 0.060), (0.14, 0.056, 0.058), (0.20, 0.057, 0.059), (0.26, 0.060, 0.063), (0.32, 0.063, 0.066),
    (0.375, 0.066, 0.069)]


def build_boots(metal):
    """The old shoe is the foot; its ankle rises into a tall shaft. Lacing up the front, two buckled straps."""
    src = OLD['Boots']
    bm = bmesh.new()
    bm.from_mesh(src.data)
    col = bm.verts.layers.float_color.new('col')
    for v in bm.verts:
        v[col] = (1, 1, 1, 0)
    # the opening ring of each shoe (top boundary above the sole)
    top = [v for e in bm.edges if e.is_boundary for v in e.verts if v.co.z > 0.06]
    top = list({v.index: v for v in top}.values())
    rings = {}
    for s in (1, -1):
        loop = [v for v in top if v.co.x * s > 0]
        ax0 = Vector((0.115 * s, 0.085, 0))
        loop.sort(key=lambda v: math.atan2((v.co.x - ax0.x) * s, -(v.co.y - ax0.y)))
        rings[s] = loop
    # ankle part of the shoe: widen it to the shaft
    for v in bm.verts:
        if v.co.z > 0.075:
            s = 1 if v.co.x > 0 else -1
            ax = Vector((0.113 * s, 0.083, v.co.z))
            d = v.co - ax; d.z = 0
            if d.length < 1e-5:
                continue
            ang = math.atan2(d.x * s, -d.y)
            rx, ry = table_at(SHAFT, v.co.z)
            target = ax + Vector((s * math.sin(ang) * rx, -math.cos(ang) * ry, 0))
            k = smooth(0.075, 0.12, v.co.z)
            v.co = v.co.lerp(target, k)
    # extrude the shaft
    for s in (1, -1):
        prev = rings[s]
        z0 = max(v.co.z for v in prev)
        zs = [z0 + (SHAFT_TOP - z0) * k / 9 for k in range(1, 10)]
        for z in zs:
            ax = Vector((0.113 * s, 0.083 + (z - 0.1) * 0.06, z))
            rx, ry = table_at(SHAFT, z)
            new = []
            for v in prev:
                d = v.co - Vector((ax.x, v.co.y if False else ax.y, v.co.z)); d.z = 0
                ang = math.atan2(d.x * s, -d.y)
                nv = bm.verts.new(ax + Vector((s * math.sin(ang) * rx, -math.cos(ang) * ry, 0)))
                nv[col] = (1, 1, 1, 0)
                new.append(nv)
            for k in range(len(prev)):
                k1 = (k + 1) % len(prev)
                try:
                    f = bm.faces.new([prev[k], prev[k1], new[k1], new[k]])
                    f.smooth = True
                except ValueError:
                    pass
            prev = new
        # rolled top edge, turned 1 cm inside
        inner = []
        for v in prev:
            ax = Vector((0.113 * s, 0.083 + (SHAFT_TOP - 0.1) * 0.06, SHAFT_TOP))
            d = v.co - ax; d.z = 0
            nv = bm.verts.new(v.co - d.normalized() * 0.005 - Vector((0, 0, 0.012)))
            nv[col] = (0.5, 0.5, 0.5, 0)
            inner.append(nv)
        for k in range(len(prev)):
            k1 = (k + 1) % len(prev)
            try:
                f = bm.faces.new([prev[k1], prev[k], inner[k], inner[k1]])
                f.smooth = True
            except ValueError:
                pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new('Boots')
    bm.to_mesh(me)
    ob = bpy.data.objects.new('Boots', me)
    bpy.context.scene.collection.objects.link(ob)
    attr = me.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
    for i, v in enumerate(bm.verts):
        c = v[col]
        # the sole (lowest 2.5 cm, and the old sole shell) is rubber: tag it darker, matte via alpha 0.5
        sole = v.co.z < 0.022
        attr.data[i].color = (0.55, 0.55, 0.55, 0.5) if sole else tuple(c)
    me.color_attributes.active_color = attr
    # UVs in metres: around the leg / along the foot
    uvl = me.uv_layers.new(name='UVMap')
    for p in me.polygons:
        for li in p.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            s = 1 if co.x > 0 else -1
            uvl.data[li].uv = (math.atan2((co.x - 0.113 * s) * s, -(co.y - 0.083)) * 0.06 + co.y * 0.3, co.z)
    me.materials.append(bpy.data.materials.get('leather') or bpy.data.materials.new('leather'))
    # laces, eyelets and straps
    bvh = BVHTree.FromObject(ob, bpy.context.evaluated_depsgraph_get())
    lace = MB('Laces')

    def surf(s, z, dx):
        """Point on the front of the boot at height z, dx sideways from the lacing line."""
        x = 0.113 * s + dx
        o = Vector((x, -0.4, z))
        hit = bvh.ray_cast(o, Vector((0, 1, 0)), 1.0)
        return (hit[0], hit[1]) if hit[0] is not None else (None, None)

    for s in (1, -1):
        zs = [0.07 + 0.024 * k for k in range(13)]
        eyes = []
        for z in zs:
            row = []
            for dx in (-0.017, 0.017):
                p, n = surf(s, z, dx)
                if p is not None:
                    row.append((p + n * 0.0015, n))
            if len(row) == 2:
                eyes.append(row)
        # tongue: a darker strip behind the laces
        for k in range(len(eyes) - 1):
            a0, a1 = eyes[k][0][0], eyes[k][1][0]
            b0, b1 = eyes[k + 1][0][0], eyes[k + 1][1][0]
            vs = [lace.v(p, (0.6, 0.6, 0.6, 0)) for p in (a0 + eyes[k][0][1] * -0.0008, a1 + eyes[k][1][1] * -0.0008,
                                                          b1 + eyes[k + 1][1][1] * -0.0008, b0 + eyes[k + 1][0][1] * -0.0008)]
            lace.f(vs, [(0, 0), (0.03, 0), (0.03, 0.03), (0, 0.03)])
        for k, row in enumerate(eyes):
            for p, n in row:
                metal.tube([p - n * 0.001, p + n * 0.0025], 0.0032, 6, (0.6, 0.6, 0.62, 0), caps=True, up=Vector((0, 0, 1)))
            if k + 1 < len(eyes):
                # criss-cross: left eye to the next right eye and back
                for (pa, na), (pb, nb) in ((row[0], eyes[k + 1][1]), (row[1], eyes[k + 1][0])):
                    mid = (pa + pb) / 2 + (na + nb).normalized() * 0.003
                    lace.tube([pa + na * 0.002, mid, pb + nb * 0.002], 0.0018, 4, (0.35, 0.35, 0.35, 0))
        # a bow at the top
        if eyes:
            p, n = eyes[-1][0]
            q, m = eyes[-1][1]
            c = (p + q) / 2 + (n + m).normalized() * 0.004
            for a in (-1, 1):
                lace.tube([c, c + Vector((a * 0.018, -0.006, 0.012)), c + Vector((a * 0.026, -0.008, -0.004)), c], 0.002, 4, (0.35, 0.35, 0.35, 0))
                lace.tube([c, c + Vector((a * 0.01, -0.01, -0.04))], 0.0018, 4, (0.35, 0.35, 0.35, 0))
        # two straps with buckles on the outer side
        for zc in (0.215, 0.31):
            ax = Vector((0.113 * s, 0.083 + (zc - 0.1) * 0.06, zc))
            rx, ry = table_at(SHAFT, zc)
            ring0, ring1 = [], []
            for k in range(29):
                ang = TAU * k / 28
                d = Vector((s * math.sin(ang), -math.cos(ang), 0))
                tilt = 0.008 * math.sin(ang)
                ring0.append(ax + Vector((d.x * (rx + 0.0035), d.y * (ry + 0.0035), -0.011 + tilt)))
                ring1.append(ax + Vector((d.x * (rx + 0.0035), d.y * (ry + 0.0035), 0.011 + tilt)))
            lace.grid([ring0, ring1], [[(0.75, 0.75, 0.75, 0)] * 29] * 2, [[(k * 0.015, 0) for k in range(30)], [(k * 0.015, 0.022) for k in range(30)]])
            # buckle frame on the outer side
            bc = ax + Vector((s * (rx + 0.006), 0.0, 0.008 * 1.0))
            out = Vector((s, 0, 0))
            for dy, dz, hy, hz in ((-0.013, 0, 0.0018, 0.015), (0.013, 0, 0.0018, 0.015), (0, 0.014, 0.013, 0.0018), (0, -0.014, 0.013, 0.0018)):
                metal.box(bc + Vector((0, dy, dz)), out * 0.002, Vector((0, hy, 0)), Vector((0, 0, hz)), (0.7, 0.7, 0.72, 0))
            metal.box(bc + Vector((0, 0.0, 0)), out * 0.0025, Vector((0, 0.0015, 0)), Vector((0, 0, 0.013)), (0.7, 0.7, 0.72, 0))
            # strap tail beyond the buckle
            metal_tail = ax + Vector((s * (rx + 0.0055), -0.03, 0.0))
            lace.box(metal_tail, Vector((s * 0.0015, 0, 0)), Vector((0, 0.018, 0)), Vector((0, 0, 0.0105)), (0.75, 0.75, 0.75, 0))
        # pull tab at the back of the shaft
        ax = Vector((0.113 * s, 0.083 + (SHAFT_TOP - 0.1) * 0.06, SHAFT_TOP))
        lace.box(ax + Vector((0, table_at(SHAFT, SHAFT_TOP)[1] + 0.002, 0.006)), Vector((0.009, 0, 0)), Vector((0, 0.002, 0)), Vector((0, 0, 0.018)), (0.8, 0.8, 0.8, 0))
    laces = lace.obj('leather')
    return ob, laces


# ------------------------------------------------------------------------------------------------- skin weights
def weights_from(target, sources, k=6):
    """Copy skin weights from the nearest vertices of the old garments (inverse distance over k neighbours)."""
    pts = []
    for src in sources:
        me = src.data
        names = [g.name for g in src.vertex_groups]
        for v in me.vertices:
            w = {names[g.group]: g.weight for g in v.groups if g.weight > 0.001}
            if w:
                pts.append((src.matrix_world @ v.co, w))
    kd = KDTree(len(pts))
    for i, (p, _) in enumerate(pts):
        kd.insert(p, i)
    kd.balance()
    for b in ARM.data.bones:
        if b.name not in target.vertex_groups:
            target.vertex_groups.new(name=b.name)
    for v in target.data.vertices:
        acc = {}
        tot = 0.0
        for (co, i, d) in kd.find_n(target.matrix_world @ v.co, k):
            wd = 1.0 / (d + 0.004) ** 2
            tot += wd
            for g, w in pts[i][1].items():
                acc[g] = acc.get(g, 0.0) + w * wd
        top = sorted(acc.items(), key=lambda kv: -kv[1])[:4]
        s = sum(w for _, w in top) or 1.0
        for g, w in top:
            target.vertex_groups[g].add([v.index], w / s, 'REPLACE')


BODY_BONES = ('pelvis', 'spine_01', 'spine_02', 'spine_03', 'neck_01', 'clavicle_l', 'clavicle_r')


def keep_bones(ob, allowed):
    for v in ob.data.vertices:
        gs = [(ob.vertex_groups[g.group].name, g.weight) for g in v.groups]
        tot = sum(w for n, w in gs if n in allowed)
        for n, w in gs:
            if n not in allowed:
                ob.vertex_groups[n].remove([v.index])
            elif tot > 0:
                ob.vertex_groups[n].add([v.index], w / tot, 'REPLACE')
        if tot <= 0:
            ob.vertex_groups['spine_01'].add([v.index], 1.0, 'REPLACE')


def body_below(ob, z0=1.30, z1=1.36):
    """The hoodie body hangs from the spine and pelvis; only the shoulders and sleeves (high, in the T-pose) follow
    the arms. Without this the sides of the loose hoodie fold into the body when the arms come down."""
    for v in ob.data.vertices:
        k = smooth(z0, z1, v.co.z)   # 0: body only
        gs = [(ob.vertex_groups[g.group].name, g.weight) for g in v.groups]
        body = sum(w for n, w in gs if n in BODY_BONES)
        if k >= 1 or not gs:
            continue
        new = {}
        for n, w in gs:
            if n in BODY_BONES:
                new[n] = w * (k + (1 - k) / max(body, 1e-6)) if body > 0 else w * k
            else:
                new[n] = w * k
        if body <= 0:
            new['spine_02'] = new.get('spine_02', 0.0) + (1 - k)
        t = sum(new.values()) or 1.0
        for n in [x for x, _ in gs]:
            ob.vertex_groups[n].remove([v.index])
        for n, w in new.items():
            if w > 1e-4:
                ob.vertex_groups[n].add([v.index], w / t, 'REPLACE')


def waist_from(ob, src, z0=0.97, z1=1.04):
    """Below z1 the weights blend into those of the nearest vertex of src (the jeans), fully at z0."""
    kd = KDTree(len(src.data.vertices))
    for v in src.data.vertices:
        kd.insert(v.co, v.index)
    kd.balance()
    sn = [g.name for g in src.vertex_groups]
    for v in ob.data.vertices:
        k = smooth(z1, z0, v.co.z)
        if k <= 0:
            continue
        co, i, d = kd.find(v.co)
        sw = {sn[g.group]: g.weight for g in src.data.vertices[i].groups}
        cur = {ob.vertex_groups[g.group].name: g.weight for g in v.groups}
        mix = {}
        for n in set(sw) | set(cur):
            mix[n] = cur.get(n, 0.0) * (1 - k) + sw.get(n, 0.0) * k
        top = sorted(mix.items(), key=lambda kv: -kv[1])[:4]
        t = sum(w for _, w in top) or 1.0
        for n in cur:
            ob.vertex_groups[n].remove([v.index])
        for n, w in top:
            ob.vertex_groups[n].add([v.index], w / t, 'REPLACE')


def rig(ob):
    ob.parent = ARM
    m = ob.modifiers.new('Armature', 'ARMATURE')
    m.object = ARM


def shaft_weights(ob):
    """The boot shaft follows the shin (the old shoe had nothing up there)."""
    for v in ob.data.vertices:
        if v.co.z > 0.11:
            s = 'l' if v.co.x > 0 else 'r'
            k = smooth(0.11, 0.17, v.co.z)
            for g in list(v.groups):
                name = ob.vertex_groups[g.group].name
                ob.vertex_groups[g.group].add([v.index], g.weight * (1 - k), 'REPLACE')
            ob.vertex_groups['calf_' + s].add([v.index], k, 'ADD')


# ------------------------------------------------------------------------------------------------- build
metal = MB('Metal')
torso = build_torso()
crop = build_crop()
hood_body, hood_rows = build_hoodie()
sleeves = build_sleeves()
hood = build_hood()
zipper = build_zipper(hood_rows)
pockets = build_pockets(hood_rows)
strings = build_strings(metal)
jeans = build_jeans(metal)
boots, laces = build_boots(metal)
metal_ob = metal.obj('metal')

# one hoodie mesh: body, sleeves, pockets and the hood
bpy.ops.object.select_all(action='DESELECT')
for o in (hood_body, sleeves, pockets, hood):
    o.select_set(True)
bpy.context.view_layer.objects.active = hood_body
bpy.ops.object.join()
hoodie = hood_body
hoodie.name = 'Hoodie'
bpy.ops.object.select_all(action='DESELECT')
for o in (boots, laces):
    o.select_set(True)
bpy.context.view_layer.objects.active = boots
bpy.ops.object.join()

SRCW = {
    'Torso': [OLD['Hoodie']], 'CropTop': [OLD['Hoodie']], 'Hoodie': [OLD['Hoodie'], OLD['Hood'], OLD['Collar']],
    'Zipper': [OLD['Hoodie']], 'Strings': [OLD['Strings'], OLD['Collar']], 'Jeans': [OLD['Jeans']],
    'Boots': [OLD['Boots'], OLD['Jeans']], 'Metal': [OLD['Jeans'], OLD['Boots'], OLD['Strings'], OLD['Hoodie']],
}
NEW = {'Jeans': jeans, 'Torso': torso, 'CropTop': crop, 'Hoodie': hoodie, 'Zipper': zipper, 'Strings': strings,
       'Boots': boots, 'Metal': metal_ob}
for name, ob in NEW.items():
    ob.name = name
    ob.data.name = name
    weights_from(ob, SRCW[name])
    if name == 'Boots':
        shaft_weights(ob)
    if name in ('Torso', 'CropTop'):
        keep_bones(ob, BODY_BONES)
    if name == 'Torso':
        waist_from(ob, NEW['Jeans'])
    if name in ('Hoodie', 'Zipper', 'Strings'):
        body_below(ob)
    rig(ob)
    print('MESH', name, len(ob.data.vertices), 'verts', len(ob.data.polygons), 'faces')

for o in list(bpy.context.scene.objects):
    if o.type == 'MESH' and o.name not in NEW or o.type == 'EMPTY' and o.name.startswith('Ico'):
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.object.select_all(action='DESELECT')
for o in NEW.values():
    o.select_set(True)
ARM.select_set(True)
bpy.context.view_layer.objects.active = ARM
bpy.ops.export_scene.gltf(filepath=OUT, use_selection=True, export_format='GLB', export_texcoords=True, export_normals=True,
                          export_vertex_color='ACTIVE', export_all_vertex_colors=True, export_materials='PLACEHOLDER',
                          export_skins=True, export_yup=True, export_animations=False)
print('OK', OUT)
