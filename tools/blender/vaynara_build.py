"""Vaynara, rebuilt to the owner's reference picture (run: python3 tools/blender/vaynara_build.py).

Realistic body and head from MakeHuman's CC0 assets (tools/blender/mh_human.py): slim tall young woman, natural
skin (skins01 "callharvey3d midtoned female", CC0), blue-grey eyes, natural brows and lashes, a straight blonde bob
(system hair "bob02", tinted honey blonde with darker roots). Hands stay from the old model (hidden at the cuffs).
Clothes are separate meshes built around that body:
  CropTop  dark red strapless bandeau over the bust; midriff bare
  Hoodie   short warm-taupe zip hoodie worn open: ribbed hem at the waist, ribbed cuffs with bunched forearms,
           silver zip on both edges, hood bunched up behind the neck, split pockets
  Jeans    very dark indigo skinny jeans, low waistband, button, rivets, loops, back pockets, seams
  Boots    knee-high black worn leather, three buckled straps at the top and one round the ankle, chunky sole
  Metal    button, rivets, buckles, zip pulls
Input: the old character exported from Godot (tools/export_character_glb.gd -> /home/claude/work/vay/vaynara.glb).
Output: /home/claude/work/vay/vaynara_outfit.glb; tools/build_vaynara.gd puts it on the original skeleton.

Blender space: z up, the character faces -y, its left is +x, T-pose arms along x at z 1.418.
Garment vertex data for shaders/garment.gdshader: UV in metres, COLOR.rgb shade, COLOR.a = 1 on ribbed knit.
"""
import bpy, bmesh, math, os, sys
import numpy as np
from mathutils import Vector
from mathutils.kdtree import KDTree
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mh_human as mh

SRC = '/home/claude/work/vay/vaynara.glb'
OUT = '/home/claude/work/vay/vaynara_outfit.glb'
SKIN_TEX_DIR = '/home/claude/dl/mh/skins01/x/skins/callharvey3d_midtoned_female'
TAU = math.tau


def smooth(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def table_at(table, z):
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


# ------------------------------------------------------------------------------------------------- the human
MH_TARGETS = [
    ('macrodetails/caucasian-female-young.target', 1.0),
    ('macrodetails/universal-female-young-averagemuscle-minweight.target', 0.4),
    ('macrodetails/height/female-young-averagemuscle-averageweight-maxheight.target', 0.45),
    ('macrodetails/proportions/female-young-averagemuscle-averageweight-idealproportions.target', 0.9),
    ('stomach/stomach-tone-incr.target', 0.35),
]
HV, HVT, HF = mh.human(MH_TARGETS)
HG = mh.groups(HF)
RW = mh.rig_weights()
_neck = mh.joint(HV, HG, 'neck')
_pel = mh.joint(HV, HG, 'pelvis')
S = (1.485 - 0.932) / (_neck[1] - _pel[1])
TR = np.array([0.0, 0.041 + _neck[2] * S, 1.485 - _neck[1] * S])


def ours(P):
    P = np.asarray(P, float)
    return np.stack([P[:, 0], -P[:, 2], P[:, 1]], 1) * S + TR


HW = ours(HV)
ARMW = np.zeros(len(HV))
LEGW = np.zeros(len(HV))
for b, (i, w) in RW.items():
    if any(k in b for k in ('upperarm', 'lowerarm', 'wrist', 'finger', 'metacarpal', 'shoulder01')):
        ARMW[i] += w
    if any(k in b for k in ('upperleg', 'lowerleg', 'foot', 'toe')):
        LEGW[i] += w
BODY_FACES = [f for f in HF if f[2] == 'body']

# --- cross sections of the body (convex hulls of plane cuts): what clothes stretch over
HULL_Z = np.round(np.arange(0.78, 1.555, 0.005), 4)
HULL_N = 120


def _hull(pts):
    pts = sorted(set(map(tuple, np.round(pts, 5))))
    if len(pts) < 3:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, up = [], []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(up) >= 2 and cross(up[-2], up[-1], p) <= 0:
            up.pop()
        up.append(p)
    return lo[:-1] + up[:-1]


def _sections():
    # edges of torso faces (no arms), legs included so the hips are right
    E = set()
    for vs, ts, g in BODY_FACES:
        if max(ARMW[v] for v in vs) > 0.5:
            continue
        for a, b in zip(vs, vs[1:] + vs[:1]):
            E.add((min(a, b), max(a, b)))
    E = np.array(sorted(E))
    A, B = HW[E[:, 0]], HW[E[:, 1]]
    R = np.zeros((len(HULL_Z), HULL_N))
    C = np.zeros(len(HULL_Z))
    for zi, z in enumerate(HULL_Z):
        m = (A[:, 2] - z) * (B[:, 2] - z) < 0
        t = (z - A[m, 2]) / (B[m, 2] - A[m, 2])
        P = A[m, :2] + (B[m, :2] - A[m, :2]) * t[:, None]
        if len(P) < 3:
            R[zi] = R[zi - 1]
            C[zi] = C[zi - 1]
            continue
        h = np.array(_hull(P))
        cy = 0.5 * (h[:, 1].min() + h[:, 1].max())
        C[zi] = cy
        for k in range(HULL_N):
            th = TAU * k / HULL_N
            d = np.array([math.sin(th), -math.cos(th)])
            best = 0.0
            for i in range(len(h)):
                p, q = h[i] - [0, cy], h[(i + 1) % len(h)] - [0, cy]
                e = q - p
                den = d[0] * e[1] - d[1] * e[0]
                if abs(den) < 1e-12:
                    continue
                tt = (p[0] * e[1] - p[1] * e[0]) / den
                u = (p[0] * d[1] - p[1] * d[0]) / den
                if tt > 0 and -1e-6 <= u <= 1 + 1e-6:
                    best = max(best, tt)
            R[zi, k] = best
    # light smoothing along z (plane cuts of a coarse mesh flicker)
    Rs = R.copy()
    for zi in range(1, len(HULL_Z) - 1):
        Rs[zi] = 0.25 * R[zi - 1] + 0.5 * R[zi] + 0.25 * R[zi + 1]
    Cs = np.convolve(np.pad(C, 2, mode='edge'), np.ones(5) / 5, mode='valid')
    return Rs, Cs


HR, HC = _sections()


def hull_r(theta, z):
    zf = (z - HULL_Z[0]) / (HULL_Z[1] - HULL_Z[0])
    zi = int(min(max(math.floor(zf), 0), len(HULL_Z) - 2))
    tz = min(max(zf - zi, 0.0), 1.0)
    tf = (theta % TAU) / TAU * HULL_N
    ti = int(math.floor(tf)) % HULL_N
    tt = tf - math.floor(tf)
    t1 = (ti + 1) % HULL_N
    r0 = HR[zi, ti] * (1 - tt) + HR[zi, t1] * tt
    r1 = HR[zi + 1, ti] * (1 - tt) + HR[zi + 1, t1] * tt
    return r0 * (1 - tz) + r1 * tz


def axis_y(z):
    zf = (z - HULL_Z[0]) / (HULL_Z[1] - HULL_Z[0])
    zi = int(min(max(math.floor(zf), 0), len(HULL_Z) - 2))
    tz = min(max(zf - zi, 0.0), 1.0)
    return HC[zi] * (1 - tz) + HC[zi + 1] * tz


def dir2(theta):
    return Vector((math.sin(theta), -math.cos(theta), 0.0))


def body_point(theta, z, off=0.0):
    return Vector((0.0, axis_y(z), z)) + dir2(theta) * (hull_r(theta, z) + off)


def axis_torso(c):
    return Vector((0.0, axis_y(c.z), c.z))


BUST_Z = float(HULL_Z[int(np.argmax(HR[:, 0] * (HULL_Z > 1.2) * (HULL_Z < 1.36)))])
print('bust apex at', BUST_Z, 'front', HR[:, 0].max())


# ------------------------------------------------------------------------------------------------- mesh helper
class MB:
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

    def grid(self, P, C=None, U=None, closed=False):
        R = len(P)
        Cn = len(P[0])
        V = [[self.v(P[i][j], C[i][j] if C else (1, 1, 1, 0)) for j in range(Cn)] for i in range(R)]
        for i in range(R - 1):
            for j in range(Cn if closed else Cn - 1):
                j1 = (j + 1) % Cn
                q = [V[i][j], V[i][j1], V[i + 1][j1], V[i + 1][j]]
                if U:
                    uv = [U[i][j], U[i][j + 1], U[i + 1][j + 1], U[i + 1][j]]
                else:
                    uv = [(0, 0)] * 4
                self.f(q, uv)
        return V

    def tube(self, path, radii, seg=10, col=(1, 1, 1, 0), caps=False, up=Vector((0, 0, 1))):
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
        c = Vector(centre)
        pts = [c + ax * sx + ay * sy + az * sz for sz in (-1, 1) for sy in (-1, 1) for sx in (-1, 1)]
        V = [self.v(p, col) for p in pts]
        for q in ((0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)):
            self.f([V[i] for i in q], [(0, 0), (0.02, 0), (0.02, 0.02), (0, 0.02)])

    def obj(self, material, recalc=True):
        if recalc:
            bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces[:])
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        attr = me.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
        cl = self.bm.verts.layers.float_color['col']
        for i, v in enumerate(self.bm.verts):
            attr.data[i].color = v[cl]
        me.color_attributes.active_color = attr
        mat = bpy.data.materials.get(material) or bpy.data.materials.new(material)
        me.materials.append(mat)
        return ob


def outward(ob, centre_fn):
    me = ob.data
    flip = sum(1 for p in me.polygons if p.normal.dot(p.center - centre_fn(p.center)) < 0)
    if flip > len(me.polygons) / 2:
        for p in me.polygons:
            p.flip()
        me.update()


# ------------------------------------------------------------------------------------------------- old model
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
ARM = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
OLD = {o.name: o for o in bpy.context.scene.objects if o.type == 'MESH'}
for _n, _o in OLD.items():
    _o.name = 'OLD_' + _n
BONES = {b.name: (ARM.matrix_world @ b.head_local, ARM.matrix_world @ b.tail_local) for b in ARM.data.bones}
HEAD_BONE = 'Head_2' if 'Head_2' in BONES else 'Head'


# ------------------------------------------------------------------------------------------------- MakeHuman parts
def mesh_from(name, P, faces, VT, material, keep=None, col_fn=None):
    """Blender mesh from fitted points P (our space) and obj faces (vertex idx, uv idx)."""
    used = {}
    verts, fl, uvs = [], [], []
    for vs, ts, g in faces:
        if keep is not None and not all(keep[v] for v in vs):
            continue
        idx = []
        for v in vs:
            if v not in used:
                used[v] = len(verts)
                verts.append(tuple(P[v]))
            idx.append(used[v])
        fl.append(idx)
        uvs.append([tuple(VT[t]) if t >= 0 else (0.0, 0.0) for t in ts])
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], fl)
    uvl = me.uv_layers.new(name='UVMap')
    k = 0
    for p, uv in zip(me.polygons, uvs):
        for li, t in zip(p.loop_indices, uv):
            uvl.data[li].uv = t
        p.use_smooth = True
    attr = me.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
    inv = {v: k for k, v in used.items()}
    for i in range(len(verts)):
        attr.data[i].color = col_fn(Vector(verts[i])) if col_fn else (1, 1, 1, 1)
    me.color_attributes.active_color = attr
    me.validate()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(bpy.data.materials.get(material) or bpy.data.materials.new(material))
    return ob


def build_skin():
    keep = (ARMW < 0.5) & (LEGW < 0.6)
    return mesh_from('Skin', HW, BODY_FACES, HVT, 'mh_skin', keep)


def build_proxy(name, mhclo, material, col_fn=None, shape=None):
    P, PT, PF = mh.fit_proxy(mhclo, HV)
    P = ours(P)
    if shape:
        P = shape(P)
    return mesh_from(name, P, PF, PT, material, None, col_fn)


def sweep_fringe(P):
    """The bob's fringe swept up and aside off her right eye (as in the reference), kept clear of the face."""
    pivot = np.array([0.025, 0.0, 1.745])
    out = P.copy()
    a = math.radians(-15)
    xmax = {}
    for p in P:
        k = round(p[2], 2)
        xmax[k] = max(xmax.get(k, 0.0), -p[0])
    ca, sa = math.cos(a), math.sin(a)
    for i, p in enumerate(P):
        front = smooth(-0.035, -0.075, p[1])
        low = smooth(1.735, 1.66, p[2])
        side = smooth(0.06, 0.0, p[0])
        w = front * low * side
        if w <= 0:
            continue
        dx, dz = p[0] - pivot[0], p[2] - pivot[2]
        nx, nz = dx * ca - dz * sa, dx * sa + dz * ca
        out[i, 0] = lerp(p[0], pivot[0] + nx, w)
        out[i, 2] = lerp(p[2], pivot[2] + nz, w)
        # no wider than the bob is at the new height
        lim = xmax.get(round(out[i, 2], 2), 0.09) - 0.004
        if -out[i, 0] > lim:
            out[i, 0] = -lim
    # keep every strand 4 mm off the skin of the head
    bm = bmesh.new()
    bm.from_mesh(SKIN_OB.data)
    bvh = BVHTree.FromBMesh(bm)
    for i, p in enumerate(out):
        if p[2] < 1.5:
            continue
        hit = bvh.find_nearest(Vector(p))
        if hit[0] is None:
            continue
        q, n = hit[0], hit[1]
        d = (Vector(p) - q).dot(n)
        if d < 0.004:
            out[i] = tuple(q + n * 0.004)
    return out


def hair_shade(p):
    # darker roots at the crown, lighter sun-bleached ends
    k = smooth(1.62, 1.75, p.z)
    s = lerp(1.08, 0.62, k)
    return (s, s, s, 1.0)


def build_hands():
    src = OLD['Body']
    me = src.data.copy()
    ob = bpy.data.objects.new('Hands', me)
    bpy.context.scene.collection.objects.link(ob)
    bm = bmesh.new()
    bm.from_mesh(me)
    kill = [v for v in bm.verts if abs(v.co.x) < 0.56]
    bmesh.ops.delete(bm, geom=kill, context='VERTS')
    bm.to_mesh(me)
    me.materials.clear()
    me.materials.append(bpy.data.materials.get('skin') or bpy.data.materials.new('skin'))
    return ob


# ------------------------------------------------------------------------------------------------- crop top
CROP_HEM, CROP_TOP = 1.218, 1.338


def build_crop():
    """Strapless bandeau: stretched over the bust (the hull bridges the cleavage), straight top edge, folded hems."""
    mb = MB('CropTop')
    SEG = 72
    zs = [CROP_HEM + (CROP_TOP - CROP_HEM) * i / 10 for i in range(11)]
    P, U, C = [], [], []
    for i, z in enumerate(zs):
        row = [body_point(TAU * j / SEG, z, 0.0035 + 0.0012 * math.sin(math.pi * i / 10)) for j in range(SEG)]
        P.append(row)
        U.append([((j - SEG / 2) / SEG * 0.75, z) for j in range(SEG + 1)])
        rib = 1.0 if i in (0, 10) else 0.0
        C.append([((0.93 + 0.07 * math.cos(TAU * j / SEG * 18 + i * 0.7)),) * 3 + (rib,) for j in range(SEG)])
    V = mb.grid(P, C, U, closed=True)
    # folded edges, turned in 7 mm so the top has thickness
    for ring, dz in ((V[0], 0.007), (V[-1], -0.007)):
        inner = []
        for v in ring:
            d = v.co - axis_torso(v.co); d.z = 0
            inner.append(mb.v(v.co - d.normalized() * 0.003 + Vector((0, 0, dz)), (0.5, 0.5, 0.5, 0)))
        for j in range(SEG):
            j1 = (j + 1) % SEG
            q = [ring[j1], ring[j], inner[j], inner[j1]] if dz > 0 else [ring[j], ring[j1], inner[j1], inner[j]]
            mb.f(q, [(0, 0), (0.01, 0), (0.01, 0.01), (0, 0.01)])
    return mb.obj('crop')


# ------------------------------------------------------------------------------------------------- hoodie
HEM = 0.972
HOFF = [(0.97, 0.014, 0.020, 0.018), (1.05, 0.020, 0.024, 0.022), (1.15, 0.026, 0.024, 0.024), (1.25, 0.024, 0.020, 0.022),
        (1.32, 0.022, 0.018, 0.020), (1.40, 0.024, 0.020, 0.020), (1.42, 0.024, 0.020, 0.020)]
OPEN = [(0.97, 0.112), (1.10, 0.106), (1.22, 0.100), (1.30, 0.094), (1.38, 0.074), (1.42, 0.064)]
YOKE_TOP = 1.42


def hood_off(theta, z):
    ew, ef, eb = table_at(HOFF, z)
    c, s = math.cos(theta), math.sin(theta)
    return ef * max(c, 0) ** 2 + eb * max(-c, 0) ** 2 + ew * s * s


def open_theta(z, xo):
    lo, hi = 0.0, math.pi / 2
    for _ in range(30):
        mid = (lo + hi) / 2
        if body_point(mid, z, hood_off(mid, z)).x < xo:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


BUST_FRONT = None


def hood_point(t, z):
    """t in [0, 1] from the left front edge, round the back, to the right front edge."""
    global BUST_FRONT
    xo = table_at(OPEN, z)[0]
    th0 = open_theta(z, xo)
    th = th0 + t * (TAU - 2 * th0)
    p = body_point(th, z, hood_off(th, z))
    c = math.cos(th)
    if c > 0 and z < BUST_Z:
        # the front panels hang from the bust instead of following the waist in
        apex = body_point(th, BUST_Z, hood_off(th, BUST_Z)).y
        fall = apex + (BUST_Z - z) * 0.05
        p.y = min(p.y, lerp(p.y, fall, smooth(0.3, 0.9, c)))
    edge = smooth(0.06, 0.0, min(t, 1 - t))
    p.y -= 0.006 * edge
    return p, th


NECK_Z = 1.505


def neck_ring(theta, extra=0.0):
    z = NECK_Z + 0.012 * max(-math.cos(theta), 0)
    return body_point(theta, z, 0.0 + extra)


def build_hoodie():
    mb = MB('Hoodie')
    NT = 72
    zs = [HEM + 0.012 * i for i in range(5)] + [HEM + 0.06 + 0.024 * i for i in range(17)]
    zs = [z for z in zs if z < YOKE_TOP] + [YOKE_TOP]
    nyoke = 5
    P, U, C = [], [], []
    for z in zs:
        row, cr = [], []
        for j in range(NT + 1):
            p, th = hood_point(j / NT, z)
            if z < HEM + 0.05:
                p = axis_torso(p) + (p - axis_torso(p)) * 0.99
            side = abs(math.sin(th))
            fold = 0.003 * math.sin(th * 9 + z * 23) * (0.4 + side) * smooth(1.35, 1.05, z)
            d = p - axis_torso(p); d.z = 0
            p = p + d.normalized() * fold
            row.append(p)
            sh = 0.92 + 10.0 * fold
            cr.append((sh, sh, sh, 1.0 if z < HEM + 0.05 else 0.0))
        P.append(row)
        C.append(cr)
        U.append([(j / NT * 1.0, z) for j in range(NT + 1)])
    # yoke over the shoulders to a collar round the neck
    base = P[-1]
    for k in range(1, nyoke + 1):
        b = k / nyoke
        row, cr = [], []
        for j in range(NT + 1):
            p0 = base[j]
            th = math.atan2(p0.x, -(p0.y - axis_y(p0.z)))
            tgt = neck_ring(th, 0.024)
            p = p0.lerp(tgt, smooth(0.0, 1.0, b))
            p.z += 0.018 * math.sin(math.pi * b) * abs(math.sin(th)) ** 0.5
            row.append(p)
            cr.append((0.95, 0.95, 0.95, 0.0))
        P.append(row)
        C.append(cr)
        U.append([(j / NT, YOKE_TOP + 0.03 * k) for j in range(NT + 1)])
    mb.grid(P, C, U)
    ob = mb.obj('hoodie')
    outward(ob, axis_torso)
    return ob, P


SLEEVE_R = [(0.115, 0.060, 0.054), (0.16, 0.062, 0.057), (0.22, 0.062, 0.058), (0.30, 0.059, 0.056), (0.39, 0.056, 0.053),
            (0.46, 0.054, 0.051), (0.53, 0.052, 0.049), (0.575, 0.050, 0.047), (0.585, 0.038, 0.036), (0.628, 0.035, 0.033)]


def build_sleeves():
    mb = MB('Sleeves')
    SEGS = 20
    for s in (1, -1):
        rings, C, U = [], [], []
        for k in range(23):
            x = 0.115 + k * (0.628 - 0.115) / 22
            p = Vector((s * x, 0.050, 1.418 - 0.018 * smooth(0.26, 0.12, x)))
            ry, rz = table_at(SLEEVE_R, x)
            bunch = 0.004 * math.sin(x * 95) * smooth(0.40, 0.55, x) * smooth(0.585, 0.57, x)
            ring, cr = [], []
            for j in range(SEGS):
                a = TAU * j / SEGS
                ring.append(Vector((p.x, p.y + math.cos(a) * (ry + bunch), p.z + math.sin(a) * (rz + bunch * 0.7))))
                sh = 0.92 + 18.0 * bunch * math.cos(a * 2 + x * 40)
                cr.append((sh, sh, sh, 1.0 if x > 0.582 else 0.0))
            if s < 0:
                ring.reverse(); cr.reverse()
            rings.append(ring)
            C.append(cr)
            U.append([(j / SEGS * 0.36, x) for j in range(SEGS + 1)])
        mb.grid(rings, C, U, closed=True)
    ob = mb.obj('hoodie')
    outward(ob, lambda c: Vector((c.x, 0.050, 1.418)))
    return ob


def build_hood():
    """The hood bunched up behind the neck: rises off the collar, folds over and lies down the upper back."""
    mb = MB('Hood')
    NU, NV = 22, 14
    P, C, U = [], [], []
    for i in range(NV + 1):
        v = i / NV
        row, cr = [], []
        for j in range(NU + 1):
            u = j / NU * 2 - 1
            th = math.pi - u * 1.45
            a = neck_ring(th, 0.026)
            a.z -= 0.004
            back = axis_y(1.52) + hull_r(math.pi, 1.52)
            # the empty hood stands up round the back of the neck (to the ears) before folding down the back
            b = Vector((u * 0.125, back + 0.075 - 0.015 * u * u, 1.60 - 0.05 * u * u))
            zc = 1.405 + 0.05 * u * u
            c = Vector((u * 0.10, axis_y(zc) + hull_r(math.pi - u * 0.6, zc) * 0.98 + table_at(HOFF, zc)[2] + 0.006, zc))
            # quadratic bezier collar -> top fold -> lying on the back
            p = a * (1 - v) ** 2 + b * 2 * v * (1 - v) + c * v * v
            p.y += 0.006 * math.sin(u * 6 + v * 5) * math.sin(math.pi * v)
            row.append(p)
            sh = 0.75 + 0.25 * math.sin(math.pi * min(v * 1.3, 1.0))
            cr.append((sh, sh, sh, 0))
        P.append(row)
        C.append(cr)
        U.append([(j / NU * 0.55, v * 0.32) for j in range(NU + 1)])
    mb.grid(P, C, U)
    # collar band from one front edge round the neck to the other
    NC = 44
    th0 = open_theta(YOKE_TOP, table_at(OPEN, YOKE_TOP)[0]) * 0.8
    band = []
    for k in range(2):
        row = []
        for j in range(NC + 1):
            th = th0 + j / NC * (TAU - 2 * th0)
            p = neck_ring(th, 0.022 + 0.012 * k)
            p.z += -0.02 + (0.04 + 0.025 * max(-math.cos(th), 0.0)) * k
            row.append(p)
        band.append(row)
    mb.grid(band, [[(1.0, 1.0, 1.0, 1.0)] * (NC + 1)] * 2, [[(j / NC * 0.45, k * 0.04) for j in range(NC + 1)] for k in range(2)])
    ob = mb.obj('hoodie')
    outward(ob, lambda c: Vector((0, axis_y(min(c.z, 1.55)), c.z)))
    return ob


def build_zipper(rows):
    mb = MB('Zipper')
    for j in (0, -1):
        R, U = [], []
        L = 0.0
        prev = None
        for row in rows:
            p = row[j]
            q = row[1 if j == 0 else -2]
            inward = (q - p).normalized()
            out = p - axis_torso(p); out.z = 0; out.normalize()
            a = p + out * 0.002 - inward * 0.0035
            b = p + out * 0.002 + inward * 0.008
            if prev is not None:
                L += (p - prev).length
            prev = p
            R.append([a, b])
            U.append([(0, L), (1, L)])
        mb.grid(R, None, U)
    ob = mb.obj('zipper')
    outward(ob, axis_torso)
    return ob


def build_pockets(rows, metal):
    """Split pockets low on the front panels with a slanted opening."""
    mb = MB('Pockets')
    NT = len(rows[0]) - 1
    idx = [i for i, r in enumerate(rows) if HEM + 0.05 <= r[0].z <= HEM + 0.15]
    for side in (0, 1):
        P, C, U = [], [], []
        for n, i in enumerate(idx):
            row = rows[i]
            f_end = 0.11 - 0.04 * n / max(len(idx) - 1, 1)
            cols = []
            for c in range(7):
                f = 0.014 + c / 6 * (f_end - 0.014)
                tt = f if side == 0 else 1 - f
                jj = tt * NT
                j0 = int(min(jj, NT - 1))
                p = row[j0].lerp(row[j0 + 1], jj - j0)
                out = p - axis_torso(p); out.z = 0; out.normalize()
                cols.append(p + out * 0.004)
            if side == 1:
                cols.reverse()
            P.append(cols)
            C.append([(0.86, 0.86, 0.86, 0)] * 7)
            U.append([(c * 0.02, row[0].z) for c in range(8)])
        if len(P) >= 2:
            mb.grid(P, C, U)
    ob = mb.obj('hoodie')
    outward(ob, axis_torso)
    return ob


# ------------------------------------------------------------------------------------------------- jeans
WAIST = 0.968
CROTCH = 0.815
LEG = sorted([(0.80, 0.086, 0.090), (0.74, 0.078, 0.082), (0.68, 0.071, 0.075), (0.62, 0.064, 0.068),
              (0.56, 0.057, 0.061), (0.52, 0.054, 0.058), (0.47, 0.052, 0.057), (0.42, 0.052, 0.058),
              (0.36, 0.049, 0.054), (0.30, 0.045, 0.049)])


def leg_axis(z, s):
    th0, th1 = BONES['thigh_l']
    c0, c1 = BONES['calf_l']
    if z >= th1.z:
        p = th1.lerp(th0, (z - th1.z) / (th0.z - th1.z))
    else:
        p = c1.lerp(c0, (z - c1.z) / (c0.z - c1.z))
    return Vector((p.x * s, p.y, z))


_SKIN_BVH = None


def skin_r(theta, z):
    """Distance from the torso axis to the real skin (ray cast), for garments that hug concave parts."""
    global _SKIN_BVH
    if _SKIN_BVH is None:
        bm = bmesh.new()
        bm.from_mesh(SKIN_OB.data)
        _SKIN_BVH = BVHTree.FromBMesh(bm)
    o = Vector((0.0, axis_y(z), z))
    d = dir2(theta)
    best = None
    start = o
    for _ in range(4):
        hit = _SKIN_BVH.ray_cast(start, d, 0.5)
        if hit[0] is None:
            break
        best = (hit[0] - o).length
        start = hit[0] + d * 0.0005
    return best if best is not None else hull_r(theta, z)


def jeans_ring(z, off=0.0):
    hug = smooth(0.90, 0.94, z)    # the waistband follows the belly, lower down the hull (thighs, seat)
    pts = []
    for j in range(48):
        th = TAU * j / 48
        r = lerp(hull_r(th, z), min(skin_r(th, z), hull_r(th, z)), hug)
        pts.append(Vector((0.0, axis_y(z), z)) + dir2(th) * (r + 0.0045 + off))
    return pts


def build_jeans(metal):
    mb = MB('Jeans')
    zs = [WAIST - 0.0153 * i for i in range(11)]
    P = [jeans_ring(z, 0.0025 if i < 3 else 0.0) for i, z in enumerate(zs)]
    C = [[(0.78 if i < 3 else 1.0,) * 3 + (0,) for j in range(48)] for i in range(len(P))]
    for i, z in enumerate(zs):
        for j in range(48):
            th = TAU * j / 48
            x = P[i][j].x
            front = math.cos(th) > 0.3
            pocket = abs(abs(x) - (0.08 + (WAIST - z) * 0.9)) < 0.006 and z > WAIST - 0.085 and front and i > 2
            fly = abs(x - 0.02) < 0.005 and z > WAIST - 0.12 and front and i > 2
            if pocket or fly:
                c = C[i][j]
                C[i][j] = (c[0] * 0.55, c[1] * 0.55, c[2] * 0.55, 0)
    U = [[((j - 24) / 48 * 0.8, z) for j in range(49)] for z in zs]
    V = mb.grid(P, C, U, closed=True)
    ring = V[-1]
    for s in (1, -1):
        idx = list(range(0, 25)) if s > 0 else [0] + list(range(47, 23, -1))
        loop = [ring[k].co.copy() for k in idx]
        fb, ff = loop[-1], loop[0]
        seam = [Vector((0.002 * s, fb.lerp(ff, q / 8).y, CROTCH - 0.045 * math.sin(math.pi * q / 8))) for q in range(1, 8)]
        loopv = [ring[k] for k in idx] + [mb.v(p) for p in seam]
        n = len(loopv)
        rows = [loopv]
        for z in [0.80 - 0.03 * k for k in range(18)]:
            ax = leg_axis(z, s)
            rx, ry = table_at(LEG, z)
            row = []
            for q in range(n):
                phi = math.pi * q / 24 if q <= 24 else math.pi + math.pi * (q - 24) / 8
                p = ax + Vector((s * math.sin(phi) * rx, -math.cos(phi) * ry, 0))
                wr = 0.002 * math.sin(phi * 3 + z * 60) * smooth(0.6, 0.5, z) * smooth(0.40, 0.48, z)
                p += Vector((s * math.sin(phi), -math.cos(phi), 0)) * wr
                b = smooth(CROTCH, CROTCH - 0.10, z)
                if b < 1:
                    p = loopv[q].co.lerp(p, b)
                    p.z = lerp(loopv[q].co.z, z, b)
                row.append(mb.v(p, (1, 1, 1, 0)))
            rows.append(row)
        for i in range(len(rows) - 1):
            for q in range(n):
                q1 = (q + 1) % n
                a, b_, c, d = rows[i][q], rows[i][q1], rows[i + 1][q1], rows[i + 1][q]
                quad = [a, b_, c, d] if s > 0 else [b_, a, d, c]
                u0, u1 = q / n * 0.5, (q + 1) / n * 0.5
                uv = [(u0, a.co.z), (u1, b_.co.z), (u1, c.co.z), (u0, d.co.z)] if s > 0 else [(u1, b_.co.z), (u0, a.co.z), (u0, d.co.z), (u1, c.co.z)]
                mb.f(quad, uv)
        for row in rows[1:]:
            row[12][mb.col] = (0.68, 0.68, 0.68, 0)
    # belt loops and back pockets
    for th in (0.62, 1.45, math.pi, TAU - 1.45, TAU - 0.62):
        p = body_point(th, WAIST - 0.022, 0.0115)
        out = dir2(th)
        tang = Vector((0, 0, 1)).cross(out).normalized()
        mb.box(p, tang * 0.006, out * 0.002, Vector((0, 0, 0.019)), (0.8, 0.8, 0.8, 0))
    for s in (1, -1):
        P2, C2, U2 = [], [], []
        for zi in range(6):
            z = WAIST - 0.04 - zi * 0.021
            row = [body_point(math.pi - s * (0.25 + k * 0.12), z, 0.0095) for k in range(6)]
            if s < 0:
                row.reverse()
            P2.append(row)
            C2.append([(0.84, 0.84, 0.84, 0)] * 6)
            U2.append([(k * 0.025, z) for k in range(7)])
        mb.grid(P2, C2, U2)
    bp = body_point(0.0, WAIST - 0.016, 0.0115)
    metal.tube([bp, bp + Vector((0, -0.004, 0))], 0.0072, 10, (0.82, 0.8, 0.76, 0), caps=True)
    for s in (1, -1):
        rp = body_point(0.75 * s, WAIST - 0.03, 0.009)
        metal.tube([rp, rp - dir2(0.75 * s) * -0.003], 0.0026, 6, (0.8, 0.72, 0.5, 0), caps=True)
    ob = mb.obj('denim')
    outward(ob, lambda c: leg_axis(c.z, 1 if c.x > 0 else -1) if c.z < CROTCH else axis_torso(c))
    return ob


# ------------------------------------------------------------------------------------------------- boots
SHAFT_TOP = 0.468
SHAFT = [(0.10, 0.056, 0.060), (0.14, 0.056, 0.058), (0.20, 0.057, 0.059), (0.26, 0.059, 0.062), (0.32, 0.061, 0.065),
         (0.38, 0.063, 0.067), (0.44, 0.065, 0.069), (0.468, 0.066, 0.070)]


def shaft_axis(z, s):
    return Vector((0.113 * s, 0.083 + (z - 0.1) * 0.06 - smooth(0.30, 0.47, z) * 0.012, z))


def build_boots(metal):
    """Knee-high pull-on boots: the old shoe is the foot, its ankle rises into a wide slouchy shaft."""
    src = OLD['Boots']
    bm = bmesh.new()
    bm.from_mesh(src.data)
    col = bm.verts.layers.float_color.new('col')
    for v in bm.verts:
        v[col] = (1, 1, 1, 0)
    top = list({v.index: v for e in bm.edges if e.is_boundary for v in e.verts if v.co.z > 0.06}.values())
    rings = {}
    for s in (1, -1):
        loop = [v for v in top if v.co.x * s > 0]
        loop.sort(key=lambda v: math.atan2((v.co.x - 0.115 * s) * s, -(v.co.y - 0.085)))
        rings[s] = loop
    for v in bm.verts:
        s = 1 if v.co.x > 0 else -1
        if v.co.z > 0.075:
            ax = shaft_axis(v.co.z, s)
            d = v.co - ax; d.z = 0
            if d.length < 1e-5:
                continue
            ang = math.atan2(d.x * s, -d.y)
            rx, ry = table_at(SHAFT, v.co.z)
            target = ax + Vector((s * math.sin(ang) * rx, -math.cos(ang) * ry, 0))
            v.co = v.co.lerp(target, smooth(0.075, 0.12, v.co.z))
        elif v.co.z < 0.014:
            # chunkier lug sole: the welt stands 3.5 mm proud all round
            c = Vector((0.113 * s, 0.0, v.co.z))
            d = v.co - c; d.z = 0
            v.co += Vector((d.x, d.y * 0.4, 0)).normalized() * 0.0035
            lug = 0.5 if (int((v.co.y + 0.2) / 0.012) % 2) else 0.62
            v[col] = (lug, lug, lug, 0.5)
    for s in (1, -1):
        prev = rings[s]
        z0 = max(v.co.z for v in prev)
        zs = [z0 + (SHAFT_TOP - z0) * k / 13 for k in range(1, 14)]
        for z in zs:
            ax = shaft_axis(z, s)
            rx, ry = table_at(SHAFT, z)
            new = []
            for v in prev:
                d = v.co - ax; d.z = 0
                ang = math.atan2(d.x * s, -d.y)
                # worn leather: soft creases round the ankle and slouch folds low on the shaft
                crease = 0.0025 * math.sin(ang * 3 + z * 70) * smooth(0.12, 0.18, z) * smooth(0.30, 0.24, z)
                nv = bm.verts.new(ax + Vector((s * math.sin(ang) * (rx + crease), -math.cos(ang) * (ry + crease), 0)))
                nv[col] = (1 - 30 * abs(crease), 1 - 30 * abs(crease), 1 - 30 * abs(crease), 0)
                new.append(nv)
            for k in range(len(prev)):
                k1 = (k + 1) % len(prev)
                try:
                    bm.faces.new([prev[k], prev[k1], new[k1], new[k]]).smooth = True
                except ValueError:
                    pass
            prev = new
        inner = []
        ax = shaft_axis(SHAFT_TOP, s)
        for v in prev:
            d = v.co - ax; d.z = 0
            nv = bm.verts.new(v.co - d.normalized() * 0.005 - Vector((0, 0, 0.014)))
            nv[col] = (0.45, 0.45, 0.45, 0)
            inner.append(nv)
        for k in range(len(prev)):
            k1 = (k + 1) % len(prev)
            try:
                bm.faces.new([prev[k1], prev[k], inner[k], inner[k1]]).smooth = True
            except ValueError:
                pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new('Boots')
    bm.to_mesh(me)
    ob = bpy.data.objects.new('Boots', me)
    bpy.context.scene.collection.objects.link(ob)
    attr = me.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
    for i, v in enumerate(bm.verts):
        attr.data[i].color = tuple(v[col])
    me.color_attributes.active_color = attr
    uvl = me.uv_layers.new(name='UVMap')
    for p in me.polygons:
        for li in p.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            s = 1 if co.x > 0 else -1
            uvl.data[li].uv = (math.atan2((co.x - 0.113 * s) * s, -(co.y - 0.083)) * 0.06 + co.y * 0.3, co.z)
    me.materials.append(bpy.data.materials.get('leather') or bpy.data.materials.new('leather'))
    # straps with buckles: three at the top of the shaft, one over the ankle
    st = MB('Straps')
    for s in (1, -1):
        for zc, h in ((0.372, 0.0105), (0.411, 0.0105), (0.448, 0.0105), (0.118, 0.0095)):
            ax = shaft_axis(zc, s)
            rx, ry = table_at(SHAFT, zc)
            if zc < 0.2:
                rx, ry = rx + 0.004, ry + 0.012
            r0, r1 = [], []
            for k in range(33):
                ang = TAU * k / 32
                tilt = 0.006 * math.sin(ang)
                d = Vector((s * math.sin(ang) * (rx + 0.0038), -math.cos(ang) * (ry + 0.0038), 0))
                r0.append(ax + d + Vector((0, 0, -h + tilt)))
                r1.append(ax + d + Vector((0, 0, h + tilt)))
            st.grid([r0, r1], [[(0.72, 0.72, 0.72, 0)] * 33] * 2, [[(k * 0.013, 0) for k in range(34)], [(k * 0.013, 0.021) for k in range(34)]])
            # buckle frame on the outer side, strap end through it
            bc = ax + Vector((s * (rx + 0.0065), 0.004, 0.0))
            o = Vector((s, 0, 0))
            for dy, dz, hy, hz in ((-0.012, 0, 0.0017, h + 0.003), (0.012, 0, 0.0017, h + 0.003), (0, h + 0.003, 0.012, 0.0017), (0, -h - 0.003, 0.012, 0.0017)):
                metal.box(bc + Vector((0, dy, dz)), o * 0.002, Vector((0, hy, 0)), Vector((0, 0, hz)), (0.62, 0.6, 0.57, 0))
            metal.box(bc, o * 0.0026, Vector((0, 0.0014, 0)), Vector((0, 0, h + 0.001)), (0.62, 0.6, 0.57, 0))
            st.box(ax + Vector((s * (rx + 0.006), -0.026, 0)), Vector((s * 0.0014, 0, 0)), Vector((0, 0.016, 0)), Vector((0, 0, h * 0.95)), (0.72, 0.72, 0.72, 0))
        ax = shaft_axis(SHAFT_TOP, s)
        st.box(ax + Vector((0, table_at(SHAFT, SHAFT_TOP)[1] + 0.002, 0.004)), Vector((0.009, 0, 0)), Vector((0, 0.002, 0)), Vector((0, 0, 0.016)), (0.8, 0.8, 0.8, 0))
    return ob, st.obj('leather')


# ------------------------------------------------------------------------------------------------- weights
BODY_BONES = ('pelvis', 'spine_01', 'spine_02', 'spine_03', 'neck_01', 'clavicle_l', 'clavicle_r')


def weights_from(target, sources, k=6):
    pts = []
    for src in sources:
        names = [g.name for g in src.vertex_groups]
        for v in src.data.vertices:
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
        acc, tot = {}, 0.0
        for (co, i, d) in kd.find_n(target.matrix_world @ v.co, k):
            wd = 1.0 / (d + 0.004) ** 2
            tot += wd
            for g, w in pts[i][1].items():
                acc[g] = acc.get(g, 0.0) + w * wd
        top = sorted(acc.items(), key=lambda kv: -kv[1])[:4]
        s = sum(w for _, w in top) or 1.0
        for g, w in top:
            target.vertex_groups[g].add([v.index], w / s, 'REPLACE')


def rigid(target, bone):
    for b in ARM.data.bones:
        if b.name not in target.vertex_groups:
            target.vertex_groups.new(name=b.name)
    target.vertex_groups[bone].add(list(range(len(target.data.vertices))), 1.0, 'REPLACE')


def keep_bones(ob, allowed, fallback='spine_02'):
    for v in ob.data.vertices:
        gs = [(ob.vertex_groups[g.group].name, g.weight) for g in v.groups]
        tot = sum(w for n, w in gs if n in allowed)
        for n, w in gs:
            if n not in allowed:
                ob.vertex_groups[n].remove([v.index])
            elif tot > 0:
                ob.vertex_groups[n].add([v.index], w / tot, 'REPLACE')
        if tot <= 0:
            ob.vertex_groups[fallback].add([v.index], 1.0, 'REPLACE')


def body_below(ob, z0=1.30, z1=1.36):
    for v in ob.data.vertices:
        k = smooth(z0, z1, v.co.z)
        gs = [(ob.vertex_groups[g.group].name, g.weight) for g in v.groups]
        if k >= 1 or not gs:
            continue
        body = sum(w for n, w in gs if n in BODY_BONES)
        new = {}
        for n, w in gs:
            new[n] = w * (k + (1 - k) / max(body, 1e-6)) if n in BODY_BONES and body > 0 else w * k
        if body <= 0:
            new['spine_02'] = new.get('spine_02', 0.0) + (1 - k)
        t = sum(new.values()) or 1.0
        for n, _ in gs:
            ob.vertex_groups[n].remove([v.index])
        for n, w in new.items():
            if w > 1e-4:
                ob.vertex_groups[n].add([v.index], w / t, 'REPLACE')


def waist_from(ob, src, z0=0.95, z1=1.02):
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
        mix = {n: cur.get(n, 0.0) * (1 - k) + sw.get(n, 0.0) * k for n in set(sw) | set(cur)}
        top = sorted(mix.items(), key=lambda kv: -kv[1])[:4]
        t = sum(w for _, w in top) or 1.0
        for n in cur:
            ob.vertex_groups[n].remove([v.index])
        for n, w in top:
            ob.vertex_groups[n].add([v.index], w / t, 'REPLACE')


def hips_rigid(ob, z0=0.88, z1=0.93):
    """Above the crotch the jeans move with the pelvis only (the thighs must not drag the waistband about)."""
    for v in ob.data.vertices:
        k = smooth(z0, z1, v.co.z)
        if k <= 0:
            continue
        gs = [(ob.vertex_groups[g.group].name, g.weight) for g in v.groups]
        moved = 0.0
        for n, w in gs:
            if n.startswith('thigh') or n.startswith('calf'):
                ob.vertex_groups[n].add([v.index], w * (1 - k), 'REPLACE')
                moved += w * k
        if moved > 0:
            ob.vertex_groups['pelvis'].add([v.index], moved, 'ADD')


def shaft_weights(ob):
    for v in ob.data.vertices:
        if v.co.z > 0.11:
            s = 'l' if v.co.x > 0 else 'r'
            k = smooth(0.11, 0.17, v.co.z)
            for g in list(v.groups):
                ob.vertex_groups[g.group].add([v.index], g.weight * (1 - k), 'REPLACE')
            ob.vertex_groups['calf_' + s].add([v.index], k, 'ADD')


def rig(ob):
    ob.parent = ARM
    m = ob.modifiers.new('Armature', 'ARMATURE')
    m.object = ARM


# ------------------------------------------------------------------------------------------------- build
metal = MB('Metal')
skin = build_skin()
SKIN_OB = skin
eyes = build_proxy('Eyes', mh.SYS + '/eyes/high-poly/high-poly.mhclo', 'mh_eye')
brows = build_proxy('Brows', mh.SYS + '/eyebrows/eyebrow001/eyebrow001.mhclo', 'mh_brow')
lashes = build_proxy('Lashes', mh.SYS + '/eyelashes/eyelashes01/eyelashes01.mhclo', 'mh_lash')
hair = build_proxy('Hair', mh.SYS + '/hair/bob02/bob02.mhclo', 'mh_hair', hair_shade, sweep_fringe)
hands = build_hands()
crop = build_crop()
hood_body, hood_rows = build_hoodie()
sleeves = build_sleeves()
hood = build_hood()
zipper = build_zipper(hood_rows)
pockets = build_pockets(hood_rows, metal)
jeans = build_jeans(metal)
boots, straps = build_boots(metal)
metal_ob = metal.obj('metal')

bpy.ops.object.select_all(action='DESELECT')
for o in (hood_body, sleeves, pockets, hood):
    o.select_set(True)
bpy.context.view_layer.objects.active = hood_body
bpy.ops.object.join()
hoodie = hood_body
bpy.ops.object.select_all(action='DESELECT')
for o in (boots, straps):
    o.select_set(True)
bpy.context.view_layer.objects.active = boots
bpy.ops.object.join()

NEW = {'Jeans': jeans, 'Skin': skin, 'Hands': hands, 'Eyes': eyes, 'Brows': brows, 'Lashes': lashes, 'Hair': hair,
       'CropTop': crop, 'Hoodie': hoodie, 'Zipper': zipper, 'Boots': boots, 'Metal': metal_ob}
O = OLD
SRCW = {
    'Jeans': [O['Jeans']], 'Skin': [O['Head'], O['Body'], O['Hoodie'], O['Jeans']], 'Hands': [O['Body']],
    'CropTop': [O['Hoodie']], 'Hoodie': [O['Hoodie'], O['Hood'], O['Collar']], 'Zipper': [O['Hoodie']],
    'Boots': [O['Boots'], O['Jeans']], 'Metal': [O['Jeans'], O['Boots'], O['Hoodie']],
}
for name, ob in NEW.items():
    ob.name = name
    ob.data.name = name
    if name in ('Eyes', 'Brows', 'Lashes', 'Hair'):
        rigid(ob, HEAD_BONE)
    else:
        weights_from(ob, SRCW[name], k=1 if name == 'Hands' else 6)
    if name == 'Boots':
        shaft_weights(ob)
    if name == 'Jeans':
        hips_rigid(ob)
    if name in ('Skin',):
        keep_bones(ob, BODY_BONES + (HEAD_BONE,))
        waist_from(ob, NEW['Jeans'], 1.0, 1.06)
    if name == 'CropTop':
        keep_bones(ob, BODY_BONES)
    if name in ('Hoodie', 'Zipper'):
        body_below(ob)
    rig(ob)
    print('MESH', name, len(ob.data.vertices), 'verts', len(ob.data.polygons), 'faces')

for o in list(bpy.context.scene.objects):
    if (o.type == 'MESH' and o.name not in NEW) or (o.type == 'EMPTY' and o.name.startswith('Ico')):
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
