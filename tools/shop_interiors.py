"""Real 3D shop interiors behind every shop window (run: python3 tools/shop_interiors.py).

Reads data/shop_rooms.json (rooms reconstructed from the shop-window panes by tools/extract_shop_rooms.gd), merges
the panes of one shop into one room, and furnishes each room for its trade: shelves with products, counters and
registers, washing machines, barber chairs, booths and stools, bottles, books, shoes, arcade cabinets, ...
Geometry is in world space, one mesh per room, written to assets/models/shops/interiors.glb. city.gd gives every
room its lamp colour and shaders/interior.gdshader shades it (vertex colour albedo, baked occlusion, lit panels).

Vertex data: COLOR.rgb albedo, COLOR.a occlusion; TEXCOORD_0 surface metres (or 0..1 on labels);
TEXCOORD_1.x part (see PART), TEXCOORD_1.y pattern for floors.
"""
import json, math, os, random
import numpy as np
import pygltflib as gl

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = '/home/claude/work/shops/interiors.glb'   # converted to assets/models/shops/interiors.scn by tools/build_shop_interiors.gd
H = 3.375  # room height (as the old interior mapping)
DMAX = 7.5  # furnish / close the room no deeper than this (further back is never seen through the window)

PART = {'matte': 0, 'floor': 1, 'gloss': 2, 'light': 3, 'screen': 4, 'label': 5, 'mirror': 6, 'wall': 7, 'glass': 8,
        'metal': 9, 'wood': 10, 'fabric': 11, 'ceiling': 12}
WALL = {'plain': 0, 'wainscot': 1, 'tile': 2, 'brick': 3, 'boards': 4}
WALL_STYLE = {'deli': 'tile', 'laundry': 'tile', 'pharmacy': 'tile', 'barber': 'tile', 'pizza': 'brick', 'diner': 'tile',
              'books': 'boards', 'cafe': 'wainscot', 'office': 'wainscot', 'lobby': 'boards', 'lobby_white': 'wainscot',
              'clothes': 'wainscot', 'shoes': 'wainscot', 'news': 'wainscot', 'bar': 'brick', 'restaurant': 'brick',
              'tattoo': 'brick', 'hardware': 'brick', 'pawn': 'brick', 'liquor': 'boards', 'cn_restaurant': 'boards',
              'cn_herbs': 'boards', 'cn_grocery': 'wainscot', 'lobby_dark': 'boards', 'electro': 'plain', 'arcade': 'plain',
              'gallery': 'plain'}
CUR = {'trade': 'shop'}
FLOOR = {'checker': 0, 'wood': 1, 'terrazzo': 2, 'carpet': 3, 'tile': 4}

# interior type index (as in the old interior textures) -> trade
TYPES = {0: 'books', 1: 'deli', 2: 'laundry', 3: 'pharmacy', 4: 'diner', 5: 'pawn', 6: 'electro', 7: 'barber',
         8: 'tattoo', 9: 'shoes', 10: 'hardware', 11: 'news', 12: 'cn_grocery', 13: 'cn_restaurant', 14: 'cn_herbs',
         15: 'lobby', 16: 'bar', 17: 'cafe', 18: 'pizza', 19: 'liquor', 20: 'office', 21: 'lobby_white',
         22: 'lobby_dark', 23: 'clothes', 24: 'arcade', 25: 'gallery', 26: 'restaurant', 27: 'books'}
LAMP = {'books': (1.0, 0.86, 0.66), 'deli': (0.95, 0.98, 1.0), 'laundry': (0.9, 0.96, 1.0), 'pharmacy': (0.94, 1.0, 1.0),
        'diner': (1.0, 0.9, 0.74), 'pawn': (1.0, 0.92, 0.76), 'electro': (0.88, 0.94, 1.0), 'barber': (1.0, 0.94, 0.84),
        'tattoo': (1.0, 0.82, 0.66), 'shoes': (1.0, 0.95, 0.88), 'hardware': (0.96, 0.98, 1.0), 'news': (1.0, 0.95, 0.85),
        'cn_grocery': (1.0, 0.78, 0.55), 'cn_restaurant': (1.0, 0.7, 0.48), 'cn_herbs': (1.0, 0.8, 0.55),
        'lobby': (1.0, 0.85, 0.62), 'bar': (1.0, 0.74, 0.46), 'cafe': (1.0, 0.86, 0.66), 'pizza': (1.0, 0.92, 0.78),
        'liquor': (1.0, 0.95, 0.86), 'office': (0.94, 0.97, 1.0), 'lobby_white': (1.0, 0.95, 0.88),
        'lobby_dark': (1.0, 0.9, 0.78), 'clothes': (1.0, 0.95, 0.9), 'arcade': (0.78, 0.65, 1.0),
        'gallery': (1.0, 0.98, 0.94), 'restaurant': (1.0, 0.78, 0.52)}


class Mesh:
    def __init__(self):
        self.V, self.N, self.C, self.U, self.U2, self.I = [], [], [], [], [], []

    def quad(self, p, n, col, part, pattern=0, uv=None, ao=(1, 1, 1, 1)):
        base = len(self.V)
        for k in range(4):
            self.V.append(p[k]); self.N.append(n)
            self.C.append((col[0], col[1], col[2], ao[k]))
            self.U.append(uv[k] if uv else (0.0, 0.0))
            self.U2.append((float(part), float(pattern)))
        self.I += [base, base + 1, base + 2, base, base + 2, base + 3]   # winding is fixed at export from the normals

    def tri(self, p, n, col, part, ao=1.0):
        base = len(self.V)
        for k in range(3):
            self.V.append(p[k]); self.N.append(n)
            self.C.append((col[0], col[1], col[2], ao))
            self.U.append((0.0, 0.0))
            self.U2.append((float(part), 0.0))
        self.I += [base, base + 1, base + 2]


class Frame:
    """Piece frame inside a room: origin (x, y, z), yaw (radians) about y. Piece axes: x right, y up, z forward."""

    def __init__(self, x=0.0, y=0.0, z=0.0, yaw=0.0):
        self.o = np.array([x, y, z], float)
        c, s = math.cos(yaw), math.sin(yaw)
        self.R = np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], float)

    def p(self, v):
        return self.o + self.R @ np.array(v, float)

    def d(self, v):
        return self.R @ np.array(v, float)

    def sub(self, x=0.0, y=0.0, z=0.0, yaw=0.0):
        f = Frame()
        f.o = self.p((x, y, z))
        c, s = math.cos(yaw), math.sin(yaw)
        f.R = self.R @ np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], float)
        return f


def box(m, F, c, s, col, part='matte', ao=(0.55, 0.95), skip=(), label_front=False):
    """Axis-aligned box in frame F: centre c, size s. ao = (bottom, top) occlusion. skip: faces to leave out."""
    cx, cy, cz = c
    hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
    y0, y1 = cy - hy, cy + hy
    def a(y):
        k = 0.0 if y1 - y0 < 1e-6 else (y - y0) / (y1 - y0)
        return ao[0] + (ao[1] - ao[0]) * k
    faces = {
        '+x': ([(hx, -hy, hz), (hx, -hy, -hz), (hx, hy, -hz), (hx, hy, hz)], (1, 0, 0), (s[2], s[1])),
        '-x': ([(-hx, -hy, -hz), (-hx, -hy, hz), (-hx, hy, hz), (-hx, hy, -hz)], (-1, 0, 0), (s[2], s[1])),
        '+y': ([(-hx, hy, hz), (hx, hy, hz), (hx, hy, -hz), (-hx, hy, -hz)], (0, 1, 0), (s[0], s[2])),
        '-y': ([(-hx, -hy, -hz), (hx, -hy, -hz), (hx, -hy, hz), (-hx, -hy, hz)], (0, -1, 0), (s[0], s[2])),
        '+z': ([(-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz)], (0, 0, 1), (s[0], s[1])),
        '-z': ([(hx, -hy, -hz), (-hx, -hy, -hz), (-hx, hy, -hz), (hx, hy, -hz)], (0, 0, -1), (s[0], s[1])),
    }
    pid = PART[part]
    on_floor = F.p((cx, cy - hy, cz))[1] < 0.01
    for name, (corners, n, (fu, fv)) in faces.items():
        if name in skip or (name == '-y' and on_floor):
            continue
        pts = [F.p((cx + q[0], cy + q[1], cz + q[2])) for q in corners]
        nn = F.d(n)
        aos = [a(cy + q[1]) for q in corners]
        if label_front and name == '+z':
            uv = [(0, 0), (1, 0), (1, 1), (0, 1)]
            m.quad(pts, nn, col, PART['label'], 0, uv, aos)
        else:
            uv = [(0, 0), (fu, 0), (fu, fv), (0, fv)]
            m.quad(pts, nn, col, pid, 0, uv, aos)


def cyl(m, F, c, r, h, col, part='matte', seg=10, ao=(0.55, 0.95), caps=True, axis='y', r_top=None):
    rt = r if r_top is None else r_top
    pid = PART[part]
    def P(u, v, w):
        if axis == 'y':
            return (c[0] + u, c[1] + v, c[2] + w)
        if axis == 'x':
            return (c[0] + v, c[1] + u, c[2] + w)
        return (c[0] + u, c[1] + w, c[2] + v)
    def Nv(u, v, w):
        if axis == 'y':
            return (u, v, w)
        if axis == 'x':
            return (v, u, w)
        return (u, w, v)
    for i in range(seg):
        a0 = 2 * math.pi * i / seg
        a1 = 2 * math.pi * (i + 1) / seg
        q = [P(math.cos(a1) * r, -h / 2, math.sin(a1) * r), P(math.cos(a0) * r, -h / 2, math.sin(a0) * r),
             P(math.cos(a0) * rt, h / 2, math.sin(a0) * rt), P(math.cos(a1) * rt, h / 2, math.sin(a1) * rt)]
        am = (a0 + a1) / 2
        n = F.d(Nv(math.cos(am), 0.0, math.sin(am)))
        m.quad([F.p(x) for x in q], n, col, pid, 0, [(i / seg, 0), ((i + 1) / seg, 0), ((i + 1) / seg, 1), (i / seg, 1)],
               (ao[0], ao[0], ao[1], ao[1]))
    if caps and seg >= 3:
        rim = [P(math.cos(2 * math.pi * i / seg) * rt, h / 2, math.sin(2 * math.pi * i / seg) * rt) for i in range(seg)]
        for i in range(1, seg - 1):
            m.tri([F.p(rim[0]), F.p(rim[i]), F.p(rim[i + 1])], F.d(Nv(0, 1, 0)), col, pid, ao[1])


def rnd_col(rng, palette):
    c = palette[rng.randrange(len(palette))]
    k = rng.uniform(0.85, 1.12)
    return (min(c[0] * k, 1), min(c[1] * k, 1), min(c[2] * k, 1))


PACK = [(0.85, 0.15, 0.12), (0.1, 0.35, 0.75), (0.95, 0.75, 0.1), (0.15, 0.6, 0.3), (0.92, 0.92, 0.9), (0.55, 0.2, 0.6),
        (0.95, 0.45, 0.1), (0.2, 0.7, 0.85), (0.3, 0.3, 0.32), (0.9, 0.6, 0.7)]
BOTTLE = [(0.25, 0.12, 0.05), (0.12, 0.3, 0.1), (0.6, 0.45, 0.15), (0.75, 0.75, 0.72), (0.35, 0.05, 0.05), (0.08, 0.08, 0.1)]
BOOKS = [(0.45, 0.1, 0.08), (0.1, 0.2, 0.4), (0.15, 0.3, 0.15), (0.5, 0.38, 0.2), (0.12, 0.12, 0.12), (0.7, 0.62, 0.45), (0.55, 0.25, 0.1)]


# ----------------------------------------------------------------------------------------------- furniture pieces
def shelving(m, F, w, d, h, levels, frame_col, goods, rng, back=True):
    """Wall / gondola shelving facing +z. goods: box / bottle / book / shoe / jar / can / folded / tool / none."""
    t = 0.025
    box(m, F, (0, h / 2, -d / 2 + t / 2), (w, h, t), frame_col, 'matte', (0.5, 0.85)) if back else None
    for sx in (-1, 1):
        box(m, F, (sx * (w / 2 - t / 2), h / 2, 0), (t, h, d), frame_col, 'matte', (0.5, 0.9))
    box(m, F, (0, 0.06, 0), (w, 0.12, d), tuple(c * 0.6 for c in frame_col), 'matte', (0.4, 0.55))
    ys = [0.12 + (h - 0.3) * i / max(levels - 1, 1) for i in range(levels)]
    for y in ys:
        box(m, F, (0, y, 0.0), (w - 2 * t, 0.02, d), frame_col, 'matte', (0.7, 0.75))
    if goods == 'none':
        return
    for li, y in enumerate(ys[:-1] if levels > 1 else ys):
        gap = (ys[li + 1] - y) if li + 1 < len(ys) else 0.35
        x = -w / 2 + t + 0.02
        while x < w / 2 - t - 0.06:
            if goods == 'box':
                bw = rng.uniform(0.07, 0.16); bh = min(rng.uniform(0.12, 0.3), gap - 0.04); bd = d * rng.uniform(0.5, 0.8)
                box(m, F, (x + bw / 2, y + 0.01 + bh / 2, d / 2 - bd / 2 - 0.01), (bw * 0.95, bh, bd), rnd_col(rng, PACK), 'matte',
                    (0.55, 0.95), skip=('-y', '-z'), label_front=True)
                x += bw
            elif goods in ('bottle', 'jar', 'can'):
                r = {'bottle': 0.035, 'jar': 0.045, 'can': 0.035}[goods] * rng.uniform(0.85, 1.15)
                bh = {'bottle': 0.26, 'jar': 0.14, 'can': 0.12}[goods] * rng.uniform(0.85, 1.15)
                bh = min(bh, gap - 0.06)
                col = rnd_col(rng, BOTTLE if goods == 'bottle' else PACK)
                zz = d / 2 - r - 0.02
                low = F.p((0, y, 0))[1] < 1.35   # tops are seen only on shelves below eye level
                cyl(m, F, (x + r, y + 0.01 + bh / 2, zz), r, bh, col, 'gloss' if goods == 'bottle' else 'label', 6, caps=low)
                if goods == 'bottle':
                    cyl(m, F, (x + r, y + 0.01 + bh + 0.04, zz), r * 0.35, 0.08, col, 'gloss', 4, caps=False)
                x += 2 * r + 0.012
            elif goods == 'book':
                bw = rng.uniform(0.025, 0.06); bh = min(rng.uniform(0.18, 0.3), gap - 0.03)
                box(m, F, (x + bw / 2, y + 0.01 + bh / 2, d / 2 - 0.12), (bw * 0.96, bh, 0.2), rnd_col(rng, BOOKS), 'matte', (0.5, 0.9), skip=('-y', '-z'))
                x += bw
            elif goods == 'shoe':
                col = rnd_col(rng, PACK + [(0.95, 0.95, 0.95), (0.08, 0.08, 0.08)])
                box(m, F, (x + 0.06, y + 0.03, d / 2 - 0.16), (0.1, 0.045, 0.26), col, 'matte', (0.6, 0.9), skip=('-y', '-z'))
                box(m, F, (x + 0.06, y + 0.085, d / 2 - 0.235), (0.09, 0.07, 0.11), col, 'matte', (0.6, 0.9), skip=('-y', '-z'))
                x += 0.2
            elif goods == 'folded':
                bw = rng.uniform(0.25, 0.35)
                col = rnd_col(rng, PACK)
                for k in range(rng.randint(3, 6)):
                    box(m, F, (x + bw / 2, y + 0.02 + k * 0.035, d / 2 - 0.18), (bw, 0.032, 0.3), col, 'fabric', (0.6, 0.9), skip=('-y', '-z'))
                x += bw + 0.05
            elif goods == 'tool':
                col = rnd_col(rng, [(0.85, 0.15, 0.1), (0.95, 0.7, 0.1), (0.2, 0.3, 0.7), (0.5, 0.5, 0.52)])
                if rng.random() < 0.5:
                    cyl(m, F, (x + 0.07, y + 0.01 + 0.09, d / 2 - 0.12), 0.07, 0.18, col, 'label', 8)
                    x += 0.16
                else:
                    box(m, F, (x + 0.1, y + 0.06, d / 2 - 0.15), (0.18, 0.11, 0.25), col, 'matte', (0.6, 0.9), skip=('-y',), label_front=True)
                    x += 0.21


def counter(m, F, w, d, h, body_col, top_col, register=True, glass_front=False, display=False, rng=None):
    box(m, F, (0, h / 2, 0), (w, h, d), body_col, 'wood' if body_col[0] > body_col[2] else 'matte', (0.4, 0.85))
    box(m, F, (0, h + 0.02, 0.01), (w + 0.04, 0.04, d + 0.04), top_col, 'gloss', (0.85, 0.95))
    box(m, F, (0, 0.05, d / 2 - 0.04), (w, 0.1, 0.06), (0.05, 0.05, 0.05), 'matte', (0.3, 0.4))
    if display:
        # glass display case with goods inside (the glass itself is left out: frame only)
        for sx in (-1, 1):
            for sz in (-1, 1):
                box(m, F, (sx * w * 0.45, h + 0.25, 0.08 + sz * d * 0.3), (0.025, 0.45, 0.025), (0.7, 0.72, 0.75), 'metal', (0.8, 0.95))
            box(m, F, (0, h + 0.47, 0.08 + sx * d * 0.3), (w * 0.9, 0.025, 0.025), (0.7, 0.72, 0.75), 'metal', (0.9, 0.95))
        if rng:
            for i in range(int(w / 0.22)):
                box(m, F, (-w * 0.42 + i * 0.22, h + 0.08, 0.1), (0.14, 0.06, 0.2), rnd_col(rng, PACK), 'gloss', (0.8, 0.9))
    if register:
        box(m, F, (w / 2 - 0.35, h + 0.12, -0.05), (0.32, 0.16, 0.3), (0.1, 0.1, 0.11), 'matte', (0.7, 0.9))
        box(m, F, (w / 2 - 0.35, h + 0.24, -0.1), (0.24, 0.1, 0.02), (0.2, 0.8, 0.4), 'screen', (0.9, 0.9))


def chair(m, F, col, seat_h=0.45, back=True, metal=(0.25, 0.25, 0.27)):
    for sx in (-0.18, 0.18):
        for sz in (-0.18, 0.18):
            box(m, F, (sx, seat_h / 2, sz), (0.03, seat_h, 0.03), metal, 'metal', (0.4, 0.8), skip=('+y',))
    box(m, F, (0, seat_h, 0), (0.42, 0.05, 0.42), col, 'matte', (0.7, 0.9))
    if back:
        box(m, F, (0, seat_h + 0.25, -0.2), (0.42, 0.45, 0.04), col, 'matte', (0.7, 0.9))


def stool(m, F, col, h=0.75):
    cyl(m, F, (0, h / 2, 0), 0.025, h, (0.6, 0.6, 0.62), 'metal', 8)
    cyl(m, F, (0, 0.02, 0), 0.2, 0.04, (0.6, 0.6, 0.62), 'metal', 12)
    cyl(m, F, (0, h, 0), 0.19, 0.08, col, 'gloss', 14)
    cyl(m, F, (0, h * 0.4, 0), 0.17, 0.02, (0.6, 0.6, 0.62), 'metal', 12, caps=False)


def table(m, F, w, d, h, top_col, leg_col=(0.15, 0.15, 0.16), round_top=False, cloth=None):
    if round_top:
        cyl(m, F, (0, h, 0), w / 2, 0.04, cloth or top_col, 'fabric' if cloth else 'gloss', 12)
        cyl(m, F, (0, h / 2, 0), 0.04, h, leg_col, 'metal', 8)
        cyl(m, F, (0, 0.02, 0), 0.25, 0.04, leg_col, 'metal', 10)
        if cloth:
            cyl(m, F, (0, h - 0.12, 0), w / 2 + 0.03, 0.24, cloth, 'fabric', 12, caps=False)
    else:
        box(m, F, (0, h, 0), (w, 0.04, d), top_col, 'wood' if top_col[0] > top_col[2] else 'gloss', (0.8, 0.95))
        for sx in (-1, 1):
            for sz in (-1, 1):
                box(m, F, (sx * (w / 2 - 0.05), h / 2, sz * (d / 2 - 0.05)), (0.04, h, 0.04), leg_col, 'metal', (0.4, 0.8))


def booth(m, F, w, col, table_col):
    """Diner booth facing +z: bench, table, bench."""
    for side, zz in ((1, -0.55), (-1, 0.55)):
        f = F.sub(0, 0, zz, 0 if side > 0 else math.pi)
        box(m, f, (0, 0.23, 0), (w, 0.46, 0.5), col, 'gloss', (0.45, 0.85))
        box(m, f, (0, 0.75, -0.22), (w, 0.6, 0.14), col, 'gloss', (0.6, 0.9))
    table(m, F, w - 0.1, 0.62, 0.74, table_col)
    box(m, F, (w * 0.3, 0.8, 0), (0.08, 0.1, 0.06), (0.8, 0.8, 0.82), 'metal', (0.8, 0.9))


def washer(m, F, col=(0.92, 0.93, 0.94), dryer=False):
    box(m, F, (0, 0.45, 0), (0.62, 0.9, 0.62), col, 'gloss', (0.5, 0.95))
    cyl(m, F, (0, 0.47, 0.315), 0.2, 0.02, (0.55, 0.57, 0.6), 'metal', 20, axis='z')
    cyl(m, F, (0, 0.47, 0.322), 0.16, 0.02, (0.12, 0.14, 0.16), 'glass', 20, axis='z')
    box(m, F, (0, 0.84, 0.3), (0.56, 0.08, 0.02), (0.2, 0.22, 0.25), 'matte', (0.9, 0.9))
    box(m, F, (0.18, 0.84, 0.312), (0.08, 0.035, 0.005), (0.3, 1.0, 0.5), 'screen', (0.9, 0.9))


def barber_chair(m, F, col=(0.5, 0.08, 0.06)):
    cyl(m, F, (0, 0.04, 0), 0.28, 0.08, (0.7, 0.7, 0.72), 'metal', 16)
    cyl(m, F, (0, 0.3, 0), 0.06, 0.45, (0.7, 0.7, 0.72), 'metal', 10)
    box(m, F, (0, 0.55, 0.02), (0.58, 0.12, 0.55), col, 'gloss', (0.6, 0.9))
    box(m, F, (0, 0.95, -0.24), (0.55, 0.7, 0.12), col, 'gloss', (0.65, 0.95))
    box(m, F, (0, 1.36, -0.26), (0.26, 0.16, 0.1), col, 'gloss', (0.8, 0.95))
    for sx in (-0.32, 0.32):
        box(m, F, (sx, 0.72, 0.02), (0.08, 0.06, 0.5), (0.7, 0.7, 0.72), 'metal', (0.7, 0.9))
    box(m, F, (0, 0.2, 0.42), (0.4, 0.04, 0.2), (0.7, 0.7, 0.72), 'metal', (0.5, 0.7))


def tv_wall(m, F, w, h, rng):
    x = -w / 2 + 0.1
    rows = [0.9, 1.6, 2.25]
    while x < w / 2 - 0.55:
        sw = rng.choice([0.5, 0.7, 0.9])
        for y in rows:
            box(m, F, (x + sw / 2, y, 0.03), (sw, sw * 0.58, 0.05), (0.03, 0.03, 0.035), 'gloss', (0.8, 0.9))
            box(m, F, (x + sw / 2, y, 0.058), (sw - 0.04, sw * 0.58 - 0.04, 0.005), rnd_col(rng, PACK), 'screen', (1, 1))
        x += sw + 0.12


def arcade_cabinet(m, F, col, rng):
    box(m, F, (0, 0.85, 0), (0.62, 1.7, 0.7), col, 'gloss', (0.4, 0.85))
    box(m, F, (0, 1.25, 0.33), (0.5, 0.42, 0.03), (0.05, 0.05, 0.05), 'gloss', (0.9, 0.9))
    box(m, F, (0, 1.25, 0.35), (0.44, 0.36, 0.005), rnd_col(rng, PACK), 'screen', (1, 1))
    box(m, F, (0, 1.82, 0.3), (0.62, 0.2, 0.06), rnd_col(rng, PACK), 'screen', (1, 1))
    box(m, F, (0, 0.95, 0.42), (0.6, 0.06, 0.25), (0.1, 0.1, 0.12), 'matte', (0.8, 0.9))
    for bx in (-0.12, 0.0, 0.12):
        cyl(m, F, (bx, 0.99, 0.45), 0.02, 0.03, rnd_col(rng, PACK), 'gloss', 8)


def frame_art(m, F, w, h, rng):
    box(m, F, (0, 0, 0.02), (w + 0.08, h + 0.08, 0.04), (0.08, 0.07, 0.06), 'wood', (0.9, 0.9))
    box(m, F, (0, 0, 0.042), (w, h, 0.005), rnd_col(rng, PACK), 'label', (1, 1))


def lamp_pendant(m, F, col=(1.0, 0.85, 0.6)):
    cyl(m, F, (0, -0.4, 0), 0.005, 0.8, (0.05, 0.05, 0.05), 'matte', 4, caps=False)
    cyl(m, F, (0, -0.85, 0), 0.06, 0.16, (0.08, 0.07, 0.06), 'metal', 10, r_top=0.03)
    cyl(m, F, (0, -0.94, 0), 0.05, 0.03, col, 'light', 10)


def lantern(m, F, col=(0.85, 0.1, 0.05)):
    cyl(m, F, (0, -0.35, 0), 0.005, 0.7, (0.05, 0.05, 0.05), 'matte', 4, caps=False)
    cyl(m, F, (0, -0.85, 0), 0.2, 0.32, col, 'light', 8)


def plant(m, F):
    cyl(m, F, (0, 0.2, 0), 0.18, 0.4, (0.35, 0.2, 0.12), 'matte', 10, r_top=0.21)
    for k in range(5):
        a = k * 1.3
        box(m, F.sub(0, 0, 0, a), (0, 0.65, 0.08), (0.2, 0.5, 0.05), (0.12, 0.35, 0.12), 'matte', (0.5, 0.9))


def mannequin(m, F, col):
    cyl(m, F, (0, 0.03, 0), 0.18, 0.04, (0.2, 0.2, 0.2), 'metal', 10)
    cyl(m, F, (0, 0.5, 0), 0.015, 1.0, (0.6, 0.6, 0.6), 'metal', 6)
    cyl(m, F, (0, 1.25, 0), 0.17, 0.55, col, 'fabric', 12, r_top=0.2)
    cyl(m, F, (0, 0.85, 0), 0.15, 0.3, (0.12, 0.13, 0.16), 'fabric', 12, r_top=0.17)
    cyl(m, F, (0, 1.6, 0), 0.05, 0.12, (0.85, 0.82, 0.78), 'gloss', 8)
    cyl(m, F, (0, 1.72, 0), 0.1, 0.18, (0.85, 0.82, 0.78), 'gloss', 10, r_top=0.07)


def clothes_rack(m, F, w, rng):
    for sx in (-w / 2, w / 2):
        cyl(m, F, (sx, 0.65, 0), 0.015, 1.3, (0.6, 0.6, 0.62), 'metal', 6)
    cyl(m, F, (0, 1.3, 0), 0.012, w, (0.6, 0.6, 0.62), 'metal', 6, axis='x')
    x = -w / 2 + 0.06
    col = rnd_col(rng, PACK)
    while x < w / 2 - 0.05:
        if rng.random() < 0.3:
            col = rnd_col(rng, PACK)
        box(m, F, (x, 0.95, 0), (0.025, 0.66, 0.48), col, 'fabric', (0.6, 0.85))
        x += 0.05


# ----------------------------------------------------------------------------------------------- the room shell
def shell(m, W, D, wall_col, floor_col, floor_pat, ceil='panels', ceil_col=(0.82, 0.82, 0.8)):
    F = Frame()
    # floor
    m.quad([F.p((0, 0, 0)), F.p((W, 0, 0)), F.p((W, 0, D)), F.p((0, 0, D))], (0, 1, 0), floor_col, PART['floor'], FLOOR[floor_pat],
           [(0, 0), (W, 0), (W, D), (0, D)], (0.85, 0.85, 0.6, 0.6))
    # back and side walls (facing into the room)
    ws = WALL[WALL_STYLE.get(CUR['trade'], 'plain')]
    m.quad([F.p((0, 0, D)), F.p((W, 0, D)), F.p((W, H, D)), F.p((0, H, D))], (0, 0, -1), wall_col, PART['wall'], ws,
           [(0, 0), (W, 0), (W, H), (0, H)], (0.55, 0.55, 0.85, 0.85))
    m.quad([F.p((0, 0, 0)), F.p((0, 0, D)), F.p((0, H, D)), F.p((0, H, 0))], (1, 0, 0), wall_col, PART['wall'], ws,
           [(0, 0), (D, 0), (D, H), (0, H)], (0.6, 0.5, 0.8, 0.85))
    m.quad([F.p((W, 0, D)), F.p((W, 0, 0)), F.p((W, H, 0)), F.p((W, H, D))], (-1, 0, 0), wall_col, PART['wall'], ws,
           [(0, 0), (D, 0), (D, H), (0, H)], (0.5, 0.6, 0.85, 0.8))
    # skirting boards
    box(m, F, (W / 2, 0.06, D - 0.012), (W, 0.12, 0.025), tuple(c * 0.4 for c in wall_col), 'matte', (0.5, 0.6))
    box(m, F, (0.012, 0.06, D / 2), (0.025, 0.12, D), tuple(c * 0.4 for c in wall_col), 'matte', (0.5, 0.6))
    box(m, F, (W - 0.012, 0.06, D / 2), (0.025, 0.12, D), tuple(c * 0.4 for c in wall_col), 'matte', (0.5, 0.6))
    # ceiling
    m.quad([F.p((0, H, D)), F.p((W, H, D)), F.p((W, H, 0)), F.p((0, H, 0))], (0, -1, 0), ceil_col, PART['ceiling'], 0 if ceil != 'none' else 1,
           [(0, 0), (W, 0), (W, D), (0, D)], (0.9, 0.9, 0.9, 0.9))
    if ceil == 'panels':
        nx = max(1, int(W / 1.8))
        nz = max(1, int(D / 1.8))
        for i in range(nx):
            for j in range(nz):
                x = (i + 0.5) * W / nx
                z = (j + 0.5) * D / nz
                box(m, F, (x, H - 0.015, z), (0.6, 0.02, 1.2), (1.0, 1.0, 0.97), 'light', (1, 1), skip=('+y',))
    elif ceil == 'tubes':
        for i in range(max(1, int(W / 2.2))):
            x = (i + 0.5) * W / max(1, int(W / 2.2))
            box(m, F, (x, H - 0.05, D * 0.5), (0.08, 0.05, D * 0.7), (1.0, 1.0, 0.98), 'light', (1, 1), skip=('+y',))


# ----------------------------------------------------------------------------------------------- layouts per trade
def furnish(m, trade, W, D, rng, panes):
    _furnish(m, trade, W, D, rng, panes)
    decorate(m, trade, W, D, rng)
    for p in panes:
        if abs(p[4] - 0.5) < 0.03 and p[1] - p[0] > 1.2:
            window_display(m, trade, p[0] + 0.15, p[1] - 0.15, rng)


def window_display(m, trade, x0, x1, rng):
    """The dressed window right behind the glass: a low plinth with what the shop wants passers-by to see."""
    F = Frame()
    w = x1 - x0
    cx = (x0 + x1) / 2
    z = 0.42
    if trade in ('pharmacy', 'shoes', 'books', 'liquor', 'electro', 'pawn', 'clothes', 'hardware', 'cn_herbs', 'gallery'):
        box(m, F, (cx, 0.2, z), (w, 0.4, 0.5), (0.85, 0.84, 0.8) if trade != 'pawn' else (0.15, 0.1, 0.08), 'wood' if trade in ('books', 'pawn', 'cn_herbs') else 'matte', (0.4, 0.9))
    else:
        return
    x = x0 + 0.25
    while x < x1 - 0.25:
        f = F.sub(x, 0.4, z + rng.uniform(-0.08, 0.08), math.pi + rng.uniform(-0.4, 0.4))
        if trade == 'pharmacy':
            if rng.random() < 0.35:   # cardboard standee
                box(m, f, (0, 0.55, 0), (0.45, 1.1, 0.02), rnd_col(rng, PACK), 'label', (0.9, 1.0), label_front=True)
                box(m, f, (0, 0.5, -0.12), (0.02, 1.0, 0.25), (0.6, 0.55, 0.45), 'matte', (0.7, 0.9))
                x += 0.6
                continue
            for k in range(3):        # a little pyramid of boxes
                for j in range(3 - k):
                    box(m, f, (-0.12 + j * 0.12 + k * 0.06, 0.06 + k * 0.12, 0), (0.11, 0.11, 0.08), rnd_col(rng, PACK), 'matte', (0.7, 0.95), label_front=True)
            x += 0.5
        elif trade == 'shoes':
            cyl(m, f, (0, 0.12, 0), 0.13, 0.24, (0.92, 0.92, 0.9), 'matte', 10)
            col = rnd_col(rng, PACK + [(0.95, 0.95, 0.95), (0.08, 0.08, 0.08)])
            box(m, f, (0, 0.265, 0), (0.1, 0.045, 0.27), col, 'matte', (0.7, 0.95))
            box(m, f, (0, 0.32, -0.07), (0.09, 0.07, 0.11), col, 'matte', (0.7, 0.95))
            x += 0.45
        elif trade == 'books':
            for k in range(rng.randint(3, 7)):
                box(m, f, (rng.uniform(-0.02, 0.02), 0.025 + k * 0.045, 0), (0.22, 0.042, 0.3), rnd_col(rng, BOOKS), 'matte', (0.7, 0.95))
            box(m, f, (0.3, 0.16, 0), (0.2, 0.3, 0.03), rnd_col(rng, BOOKS), 'label', (0.8, 0.95), label_front=True)
            x += 0.6
        elif trade == 'liquor':
            for k in range(3):
                for j in range(4 - k):
                    cyl(m, f, (-0.15 + j * 0.1 + k * 0.05, 0.13 + k * 0.27, 0), 0.04, 0.26, rnd_col(rng, BOTTLE), 'gloss', 6)
            x += 0.55
        elif trade == 'electro':
            box(m, f, (0, 0.3, 0), (0.62, 0.38, 0.06), (0.03, 0.03, 0.035), 'gloss', (0.8, 0.9))
            box(m, f, (0, 0.3, 0.032), (0.58, 0.34, 0.004), rnd_col(rng, PACK), 'screen', (1, 1))
            box(m, f, (0, 0.06, 0), (0.18, 0.12, 0.15), (0.05, 0.05, 0.05), 'matte', (0.6, 0.9))
            x += 0.75
        elif trade == 'pawn':
            if rng.random() < 0.5:
                col = rnd_col(rng, [(0.6, 0.25, 0.08), (0.1, 0.1, 0.1), (0.5, 0.1, 0.1)])
                g = f.sub(0, 0.0, 0, 0)
                cyl(m, g, (0, 0.2, 0), 0.17, 0.07, col, 'gloss', 12, axis='z')
                cyl(m, g, (0, 0.42, 0), 0.13, 0.07, col, 'gloss', 12, axis='z')
                box(m, g, (0, 0.8, 0), (0.05, 0.6, 0.03), (0.3, 0.18, 0.08), 'wood')
            else:
                box(m, f, (0, 0.12, 0), (0.35, 0.24, 0.25), rnd_col(rng, [(0.15, 0.15, 0.15), (0.6, 0.5, 0.3)]), 'gloss', (0.6, 0.95))
            x += 0.55
        elif trade == 'clothes':
            mannequin(m, F.sub(x, 0.4, z, math.pi), rnd_col(rng, PACK))
            x += 0.8
        elif trade == 'hardware':
            box(m, f, (0, 0.15, 0), (0.3, 0.3, 0.3), rnd_col(rng, [(0.85, 0.15, 0.1), (0.95, 0.7, 0.1), (0.2, 0.3, 0.7)]), 'matte', (0.6, 0.95), label_front=True)
            cyl(m, f, (0.25, 0.1, 0.05), 0.09, 0.2, rnd_col(rng, PACK), 'label', 8)
            x += 0.6
        elif trade == 'cn_herbs':
            cyl(m, f, (0, 0.14, 0), 0.1, 0.28, (0.7, 0.62, 0.45), 'gloss', 8)
            cyl(m, f, (0.22, 0.1, 0), 0.08, 0.2, (0.5, 0.15, 0.08), 'gloss', 8)
            x += 0.5
        elif trade == 'gallery':
            box(m, f, (0, 0.45, 0), (0.5, 0.65, 0.04), rnd_col(rng, PACK), 'label', (0.9, 1.0), label_front=True)
            box(m, f, (0, 0.06, -0.1), (0.4, 0.12, 0.3), (0.3, 0.2, 0.12), 'wood')
            x += 0.9


POSTER_WALLS = ('laundry', 'diner', 'cafe', 'pizza', 'bar', 'restaurant', 'barber', 'tattoo', 'office', 'pawn', 'electro',
                'arcade', 'cn_restaurant', 'lobby', 'lobby_white', 'clothes', 'news')
AISLE_SIGNS = ('deli', 'pharmacy', 'hardware', 'cn_grocery', 'liquor')
SIGN_COL = {'deli': (0.1, 0.45, 0.2), 'pharmacy': (0.05, 0.55, 0.35), 'hardware': (0.85, 0.45, 0.05), 'cn_grocery': (0.75, 0.08, 0.05),
            'liquor': (0.5, 0.08, 0.1)}


def decorate(m, trade, W, D, rng):
    """What makes a room look lived in: posters and frames, a clock, hanging aisle signs, a mat at the door."""
    F = Frame()
    backz = D - 0.02
    if trade in POSTER_WALLS:
        for side, x0, yaw in ((0, 0.015, math.pi / 2), (1, W - 0.015, -math.pi / 2)):
            z = 1.4 + rng.uniform(0, 0.8)
            while z < D - 1.2:
                if rng.random() < 0.7:
                    w = rng.uniform(0.4, 0.75); h = w * rng.uniform(1.2, 1.45)
                    if rng.random() < 0.5:
                        frame_art(m, F.sub(x0, rng.uniform(1.55, 1.85), z, yaw), w, h, rng)
                    else:   # a bare poster taped to the wall
                        box(m, F.sub(x0, rng.uniform(1.5, 1.9), z, yaw), (0, 0, 0.004), (w, h, 0.004), rnd_col(rng, PACK), 'label', (1, 1),
                            label_front=True)
                z += rng.uniform(1.3, 2.2)
    if trade not in ('arcade', 'gallery') and W > 3.0:
        # wall clock on the back wall
        cx = W * rng.uniform(0.25, 0.75)
        f = F.sub(cx, 2.65, backz, math.pi)
        cyl(m, f, (0, 0, 0.025), 0.17, 0.05, (0.1, 0.1, 0.1), 'gloss', 12, axis='z')
        cyl(m, f, (0, 0, 0.052), 0.15, 0.006, (0.92, 0.9, 0.85), 'matte', 12, axis='z')
        box(m, f, (0.0, 0.05, 0.058), (0.012, 0.1, 0.004), (0.05, 0.05, 0.05), 'matte', (1, 1))
        box(m, f, (0.035, 0.0, 0.06), (0.075, 0.01, 0.004), (0.05, 0.05, 0.05), 'matte', (1, 1))
    if trade in AISLE_SIGNS:
        col = SIGN_COL[trade]
        n_aisles = max(1, int((W - 1.8) / 2.4))
        for i in range(n_aisles):
            x = 1.3 + i * (W - 2.6) / max(n_aisles - 1, 1) if n_aisles > 1 else W * 0.5
            f = F.sub(x, 2.55, 3.3, 0)
            box(m, f, (0, 0, 0), (0.9, 0.28, 0.03), col, 'label', (1, 1), label_front=True)
            box(m, f.sub(0, 0, 0, math.pi), (0, 0, 0.0155), (0.88, 0.26, 0.001), col, 'label', (1, 1), label_front=True)
            for sx in (-0.35, 0.35):
                cyl(m, f, (sx, 0.5, 0), 0.004, 0.72, (0.2, 0.2, 0.2), 'metal', 4, caps=False)
    if trade not in ('arcade',):
        # door mat
        box(m, F, (W * 0.5, 0.006, 0.55), (1.1, 0.012, 0.7), (0.12, 0.11, 0.1), 'fabric', (0.7, 0.8))


def _furnish(m, trade, W, D, rng, panes):
    CUR['trade'] = trade
    F = Frame()
    door_x = None
    for p in panes:
        if abs(p[4] - 0.75) < 0.03:
            door_x = (p[0] + p[1]) / 2
    def clear(x, z, r=0.9):
        return door_x is None or abs(x - door_x) > r or z > 2.2
    backz = D - 0.02
    if trade in ('books',):
        shell(m, W, D, (0.55, 0.45, 0.34), (0.42, 0.3, 0.2), 'wood', 'panels', (0.7, 0.62, 0.5))
        for x in np.arange(0.6, W - 0.5, 1.0):
            shelving(m, F.sub(x, 0, backz - 0.18, math.pi), 0.98, 0.34, 2.4, 6, (0.35, 0.22, 0.12), 'book', rng)
        for z in np.arange(1.6, D - 0.8, 1.0):
            shelving(m, F.sub(0.2, 0, z, math.pi / 2), 0.98, 0.34, 2.2, 6, (0.35, 0.22, 0.12), 'book', rng)
        table(m, F.sub(W * 0.55, 0, D * 0.5, 0.3), 1.4, 0.8, 0.76, (0.45, 0.3, 0.18))
        for k in range(5):
            box(m, F.sub(W * 0.55 + rng.uniform(-0.5, 0.5), 0.8, D * 0.5 + rng.uniform(-0.25, 0.25), rng.uniform(0, 3)), (0, 0.03, 0), (0.18, 0.05, 0.25), rnd_col(rng, BOOKS))
        counter(m, F.sub(W - 0.7, 0, 1.6, -math.pi / 2), 1.4, 0.55, 0.95, (0.35, 0.22, 0.12), (0.25, 0.15, 0.08))
    elif trade in ('deli', 'cn_grocery', 'pharmacy', 'hardware', 'liquor', 'news'):
        cols = {'deli': ((0.85, 0.85, 0.82), (0.45, 0.45, 0.45), 'tile'), 'cn_grocery': ((0.62, 0.22, 0.14), (0.4, 0.3, 0.22), 'terrazzo'),
                'pharmacy': ((0.9, 0.93, 0.92), (0.8, 0.82, 0.82), 'tile'), 'hardware': ((0.7, 0.7, 0.68), (0.5, 0.5, 0.48), 'terrazzo'),
                'liquor': ((0.55, 0.42, 0.3), (0.35, 0.25, 0.16), 'wood'), 'news': ((0.75, 0.68, 0.55), (0.4, 0.33, 0.26), 'checker')}[trade]
        shell(m, W, D, cols[0], cols[1], cols[2], 'tubes' if trade in ('hardware', 'deli') else 'panels')
        goods = {'deli': 'box', 'cn_grocery': 'jar', 'pharmacy': 'box', 'hardware': 'tool', 'liquor': 'bottle', 'news': 'box'}[trade]
        fcol = {'deli': (0.8, 0.8, 0.8), 'cn_grocery': (0.4, 0.25, 0.15), 'pharmacy': (0.95, 0.95, 0.95), 'hardware': (0.15, 0.3, 0.6),
                'liquor': (0.3, 0.18, 0.1), 'news': (0.35, 0.25, 0.15)}[trade]
        # back wall: fridges for the deli, shelves for the rest
        for x in np.arange(0.65, W - 0.5, 1.25):
            if trade == 'deli':
                f = F.sub(x, 0, backz - 0.38, math.pi)
                box(m, f, (0, 1.05, 0), (1.2, 2.1, 0.75), (0.85, 0.85, 0.85), 'gloss', (0.5, 0.9))
                for sx in (-0.55, 0.0, 0.55):
                    box(m, f, (sx, 1.05, 0.38), (0.04, 1.85, 0.03), (0.75, 0.75, 0.75), 'metal', (0.6, 0.95))
                box(m, f, (0, 2.0, 0.38), (1.14, 0.06, 0.03), (0.75, 0.75, 0.75), 'metal', (0.9, 0.95))
                box(m, f, (0, 2.12, 0.385), (1.1, 0.16, 0.02), (0.15, 0.35, 0.7), 'label', (0.95, 0.95))
                shelving(m, f.sub(0, 0.12, 0.05), 1.08, 0.55, 1.85, 5, (0.75, 0.75, 0.75), 'bottle', rng, back=False)
            else:
                shelving(m, F.sub(x, 0, backz - 0.22, math.pi), 1.22, 0.42, 2.2, 5, fcol, goods, rng)
        # gondola aisles
        n_aisles = max(1, int((W - 1.8) / 2.4))
        ggoods = goods if goods in ('tool', 'box') else 'box'   # gondolas carry packets; jars and bottles stay on the walls
        for i in range(n_aisles):
            x = 1.3 + i * (W - 2.6) / max(n_aisles - 1, 1) if n_aisles > 1 else W * 0.5
            for z in np.arange(2.0, min(D - 1.4, 5.6), 1.25):
                if not clear(x, z):
                    continue
                g = F.sub(x, 0, z, math.pi / 2)
                shelving(m, g.sub(0, 0, 0.21, 0), 1.22, 0.42, 1.5, 4, fcol, ggoods, rng)
                shelving(m, g.sub(0, 0, -0.21, math.pi), 1.22, 0.42, 1.5, 4, fcol, ggoods, rng)
        counter(m, F.sub(W - 0.75, 0, 1.4, -math.pi / 2), 1.6, 0.6, 0.95, (0.25, 0.25, 0.27) if trade != 'liquor' else (0.3, 0.18, 0.1),
                (0.6, 0.6, 0.62), True, trade in ('pharmacy',))
        if trade == 'cn_grocery':
            for x in np.arange(1.0, W - 0.5, 1.5):
                lantern(m, F.sub(x, H, D * 0.4))
            for k in range(4):
                cyl(m, F.sub(0.6 + k * 0.45, 0, 1.3), (0, 0.25, 0), 0.2, 0.5, (0.75, 0.65, 0.45), 'fabric', 8)
    elif trade == 'laundry':
        shell(m, W, D, (0.82, 0.9, 0.92), (0.75, 0.75, 0.72), 'checker', 'panels')
        x = 0.45
        while x < W - 0.4:
            washer(m, F.sub(x, 0, backz - 0.33, math.pi))
            washer(m, F.sub(x, 0.92, backz - 0.33, math.pi), (0.85, 0.86, 0.88), True)
            x += 0.66
        for z in np.arange(1.4, D - 1.0, 0.66):
            washer(m, F.sub(0.33, 0, z, math.pi / 2))
        # folding table and plastic chairs along the window
        table(m, F.sub(W * 0.55, 0, D * 0.5, 0), min(2.4, W * 0.35), 0.8, 0.9, (0.85, 0.85, 0.82))
        for x in np.arange(1.2, W - 0.8, 0.55):
            if clear(x, 0.9):
                chair(m, F.sub(x, 0, 0.9, math.pi), (0.15, 0.4, 0.7))
        box(m, F.sub(W - 0.3, 0, 1.4, -math.pi / 2), (0, 0.8, 0), (0.45, 1.6, 0.4), (0.3, 0.3, 0.32), 'metal', (0.4, 0.9))
    elif trade in ('diner', 'cafe', 'pizza', 'cn_restaurant', 'restaurant', 'bar'):
        conf = {'diner': ((0.85, 0.82, 0.75), (0.8, 0.8, 0.78), 'checker', 'panels'),
                'cafe': ((0.85, 0.7, 0.52), (0.45, 0.32, 0.2), 'wood', 'pendant'),
                'pizza': ((0.82, 0.75, 0.62), (0.7, 0.68, 0.62), 'checker', 'panels'),
                'cn_restaurant': ((0.6, 0.12, 0.08), (0.35, 0.2, 0.12), 'wood', 'lantern'),
                'restaurant': ((0.5, 0.3, 0.22), (0.3, 0.2, 0.14), 'wood', 'pendant'),
                'bar': ((0.28, 0.18, 0.12), (0.22, 0.14, 0.09), 'wood', 'pendant')}[trade]
        shell(m, W, D, conf[0], conf[1], conf[2], 'panels' if conf[3] == 'panels' else 'none',
              (0.82, 0.82, 0.8) if conf[3] == 'panels' else (0.12, 0.1, 0.09))
        # counter along the back with stools (diner, bar, cafe) and back shelves
        cw = W - 1.6
        bz = backz - 1.2
        if trade in ('diner', 'bar', 'cafe', 'pizza'):
            counter(m, F.sub(W / 2, 0, bz, 0), cw, 0.6, 1.0, (0.7, 0.1, 0.08) if trade == 'diner' else (0.3, 0.18, 0.1),
                    (0.85, 0.85, 0.85) if trade == 'diner' else (0.2, 0.12, 0.07), True, trade in ('cafe', 'pizza'), rng)
            if trade in ('diner', 'bar'):
                for x in np.arange(W / 2 - cw / 2 + 0.35, W / 2 + cw / 2 - 0.3, 0.6):
                    stool(m, F.sub(x, 0, bz - 0.6), (0.75, 0.1, 0.08) if trade == 'diner' else (0.1, 0.06, 0.04))
            back = F.sub(W / 2, 0, backz - 0.2, math.pi)
            if trade == 'bar':
                shelving(m, back, cw, 0.32, 2.3, 4, (0.25, 0.15, 0.08), 'bottle', rng)
            elif trade == 'cafe':
                box(m, F.sub(W / 2 - 0.6, 1.05, bz + 0.1), (0, 0.22, 0), (0.55, 0.45, 0.45), (0.65, 0.65, 0.68), 'metal')
                shelving(m, back, cw, 0.32, 2.1, 3, (0.3, 0.2, 0.12), 'jar', rng)
            elif trade == 'pizza':
                box(m, F.sub(W / 2 + 0.8, 0, backz - 0.6), (0, 0.8, 0), (1.4, 1.6, 0.9), (0.55, 0.25, 0.15), 'matte', (0.4, 0.8))
                box(m, F.sub(W / 2 + 0.8, 0, backz - 0.6), (0, 0.75, 0.46), (0.7, 0.35, 0.02), (1.0, 0.5, 0.15), 'light', (1, 1))
            else:
                box(m, F.sub(W / 2, 1.3, backz - 0.02), (0, 0.3, 0), (cw * 0.6, 0.6, 0.04), (0.75, 0.75, 0.76), 'metal')
            for x in np.arange(0.9, W - 0.6, 1.4):
                box(m, F.sub(x, 2.2, backz - 0.02), (0, 0, 0), (0.9, 0.5, 0.03), (0.08, 0.08, 0.08), 'label', (0.95, 0.95), label_front=True)
        # tables
        z = 1.1
        while z < bz - 1.0:
            x = 1.0
            while x < W - 0.8:
                if trade == 'diner':
                    break
                if clear(x, z, 1.0):
                    if False:
                        pass
                    else:
                        rt = trade in ('cafe', 'cn_restaurant', 'restaurant', 'bar')
                        cloth = (0.85, 0.82, 0.75) if trade == 'restaurant' else ((0.75, 0.1, 0.06) if trade == 'cn_restaurant' else None)
                        table(m, F.sub(x, 0, z, 0), 0.9 if trade == 'cn_restaurant' else 0.7, 0.7, 0.75, (0.4, 0.26, 0.15), round_top=rt, cloth=cloth)
                        for a in (0.0, math.pi) if not rt else (0.0, math.pi / 2, math.pi, 3 * math.pi / 2):
                            f = F.sub(x, 0, z, a)
                            chair(m, f.sub(0, 0, -0.55, 0), (0.35, 0.22, 0.12) if trade != 'diner' else (0.7, 0.1, 0.08))
                x += 1.7
            z += 1.8
        if trade == 'diner':
            for x in np.arange(1.0, W - 1.0, 2.1):
                if clear(x, 0.9, 1.1):
                    booth(m, F.sub(x, 0, 1.15, math.pi / 2), 1.0, (0.7, 0.1, 0.08), (0.85, 0.85, 0.85))
            for z in np.arange(3.2, bz - 1.0, 2.0):
                booth(m, F.sub(0.75, 0, z, 0), 1.0, (0.7, 0.1, 0.08), (0.85, 0.85, 0.85))
        if conf[3] == 'pendant':
            for x in np.arange(1.0, W - 0.5, 1.6):
                for zz in np.arange(1.2, D - 0.8, 1.8):
                    lamp_pendant(m, F.sub(x, H, zz))
        if conf[3] == 'lantern':
            for x in np.arange(1.0, W - 0.5, 1.4):
                for zz in np.arange(1.2, D - 0.8, 1.6):
                    lantern(m, F.sub(x, H, zz))
    elif trade == 'barber':
        shell(m, W, D, (0.92, 0.92, 0.9), (0.85, 0.85, 0.85), 'checker', 'panels')
        n = max(1, int((W - 1.0) / 1.4))
        for i in range(n):
            x = 0.9 + i * 1.4
            barber_chair(m, F.sub(x, 0, backz - 1.2, math.pi))
            box(m, F.sub(x, 1.5, backz - 0.02), (0, 0, 0), (0.9, 1.1, 0.02), (0.8, 0.85, 0.9), 'mirror', (1, 1))
            box(m, F.sub(x, 0.95, backz - 0.2), (0, 0, 0), (1.0, 0.06, 0.35), (0.9, 0.9, 0.9), 'gloss')
            for k in range(4):
                cyl(m, F.sub(x - 0.3 + k * 0.18, 1.04, backz - 0.2), (0, 0, 0), 0.03, 0.14, rnd_col(rng, PACK), 'gloss', 6)
        for x in np.arange(0.8, W - 0.5, 0.6):
            if clear(x, 0.8):
                chair(m, F.sub(x, 0, 0.8, math.pi), (0.12, 0.12, 0.12))
        cyl(m, F.sub(W - 0.4, 0, 1.0), (0, 0.5, 0), 0.08, 1.0, (0.9, 0.9, 0.9), 'gloss', 10)
    elif trade == 'tattoo':
        shell(m, W, D, (0.12, 0.12, 0.14), (0.15, 0.15, 0.16), 'checker', 'panels', (0.1, 0.1, 0.1))
        for x in np.arange(0.5, W - 0.4, 0.55):
            for y in (1.3, 1.85):
                frame_art(m, F.sub(x, y, backz - 0.02, math.pi), 0.4, 0.45, rng)
        # tattoo bed and stool
        f = F.sub(W * 0.4, 0, D * 0.6, 0.4)
        box(m, f, (0, 0.35, 0), (0.6, 0.7, 1.8), (0.08, 0.08, 0.08), 'gloss', (0.4, 0.85))
        box(m, f, (0, 0.73, 0.1), (0.62, 0.08, 1.7), (0.12, 0.12, 0.12), 'gloss', (0.8, 0.95))
        stool(m, f.sub(0.6, 0, 0.3), (0.1, 0.1, 0.1), 0.55)
        box(m, f.sub(0.8, 0, -0.5), (0, 0.5, 0), (0.45, 1.0, 0.45), (0.6, 0.6, 0.62), 'metal')
        counter(m, F.sub(W - 0.8, 0, 1.5, -math.pi / 2), 1.6, 0.55, 1.0, (0.1, 0.1, 0.11), (0.3, 0.05, 0.05), True, True, rng)
        for x in np.arange(0.8, W - 1.2, 0.6):
            if clear(x, 0.8):
                chair(m, F.sub(x, 0, 0.8, math.pi), (0.3, 0.05, 0.05))
    elif trade == 'shoes':
        shell(m, W, D, (0.94, 0.94, 0.92), (0.6, 0.48, 0.34), 'wood', 'panels')
        for x in np.arange(0.65, W - 0.5, 1.25):
            shelving(m, F.sub(x, 0, backz - 0.2, math.pi), 1.22, 0.38, 2.3, 7, (0.95, 0.95, 0.95), 'shoe', rng)
        for z in np.arange(1.6, D - 0.9, 1.25):
            shelving(m, F.sub(0.2, 0, z, math.pi / 2), 1.22, 0.38, 2.3, 7, (0.95, 0.95, 0.95), 'shoe', rng)
        for x in np.arange(1.6, W - 1.0, 2.0):
            box(m, F.sub(x, 0, D * 0.5), (0, 0.22, 0), (1.4, 0.44, 0.45), (0.15, 0.15, 0.17), 'fabric', (0.5, 0.9))
        counter(m, F.sub(W - 0.7, 0, 1.5, -math.pi / 2), 1.4, 0.55, 0.95, (0.95, 0.95, 0.95), (0.3, 0.3, 0.3))
    elif trade in ('pawn', 'electro'):
        shell(m, W, D, (0.78, 0.76, 0.72) if trade == 'pawn' else (0.4, 0.42, 0.45), (0.5, 0.5, 0.5), 'terrazzo', 'tubes')
        if trade == 'electro':
            tv_wall(m, F.sub(W / 2, 0, backz - 0.06, math.pi), W - 0.4, 2.6, rng)
        else:
            # guitars on the back wall, electronics shelves on the side
            for x in np.arange(0.6, W * 0.6, 0.45):
                f = F.sub(x, 1.4, backz - 0.06, math.pi)
                col = rnd_col(rng, [(0.6, 0.25, 0.08), (0.1, 0.1, 0.1), (0.85, 0.85, 0.82), (0.5, 0.1, 0.1)])
                cyl(m, f, (0, -0.25, 0.03), 0.17, 0.06, col, 'gloss', 14, axis='z')
                cyl(m, f, (0, -0.02, 0.03), 0.13, 0.06, col, 'gloss', 14, axis='z')
                box(m, f, (0, 0.35, 0.03), (0.05, 0.6, 0.03), (0.3, 0.18, 0.08), 'wood')
            for x in np.arange(W * 0.65, W - 0.5, 1.25):
                shelving(m, F.sub(x, 0, backz - 0.22, math.pi), 1.22, 0.42, 2.2, 5, (0.2, 0.2, 0.22), 'box', rng)
        for i, x in enumerate(np.arange(1.2, W - 1.0, 2.0)):
            counter(m, F.sub(x, 0, D * 0.55, 0), 1.6, 0.6, 0.9, (0.15, 0.15, 0.16), (0.7, 0.75, 0.78), i == 0, True, rng)
    elif trade == 'clothes':
        shell(m, W, D, (0.92, 0.9, 0.88), (0.55, 0.42, 0.3), 'wood', 'panels')
        for x in np.arange(0.65, W - 0.5, 1.25):
            shelving(m, F.sub(x, 0, backz - 0.22, math.pi), 1.22, 0.42, 2.2, 4, (0.85, 0.85, 0.85), 'folded', rng)
        for z in np.arange(1.8, D - 1.0, 1.6):
            for x in np.arange(1.4, W - 1.0, 2.0):
                if clear(x, z):
                    clothes_rack(m, F.sub(x, 0, z, 0), 1.2, rng)
        for x in (0.7, W - 0.7):
            mannequin(m, F.sub(x, 0, 0.55, 0), rnd_col(rng, PACK))
    elif trade == 'arcade':
        shell(m, W, D, (0.12, 0.08, 0.2), (0.15, 0.1, 0.2), 'carpet', 'none', (0.06, 0.04, 0.1))
        for x in np.arange(0.5, W - 0.4, 0.7):
            arcade_cabinet(m, F.sub(x, 0, backz - 0.38, math.pi), rnd_col(rng, PACK), rng)
        for z in np.arange(1.5, D - 1.0, 0.8):
            arcade_cabinet(m, F.sub(0.4, 0, z, math.pi / 2), rnd_col(rng, PACK), rng)
        for x in np.arange(1.5, W - 1.0, 1.6):
            for zz in np.arange(1.2, D - 0.8, 1.8):
                box(m, F.sub(x, H - 0.03, zz), (0, 0, 0), (1.2, 0.03, 0.05), rnd_col(rng, [(1.0, 0.2, 0.8), (0.2, 0.6, 1.0)]), 'light', (1, 1))
    elif trade == 'gallery':
        shell(m, W, D, (0.95, 0.95, 0.94), (0.62, 0.62, 0.6), 'terrazzo', 'panels')
        for x in np.arange(1.0, W - 0.8, 1.6):
            frame_art(m, F.sub(x, 1.6, backz - 0.02, math.pi), rng.uniform(0.6, 1.0), rng.uniform(0.6, 1.1), rng)
        for z in np.arange(1.6, D - 1.0, 1.6):
            frame_art(m, F.sub(0.02, 1.6, z, math.pi / 2), 0.7, 0.9, rng)
        box(m, F.sub(W / 2, 0, D * 0.5), (0, 0.22, 0), (1.6, 0.44, 0.5), (0.2, 0.2, 0.22), 'fabric', (0.5, 0.9))
        for x in (W * 0.25, W * 0.75):
            box(m, F.sub(x, 0, D * 0.35), (0, 0.5, 0), (0.45, 1.0, 0.45), (0.92, 0.92, 0.92), 'matte', (0.5, 0.95))
            cyl(m, F.sub(x, 1.0, D * 0.35), (0, 0.18, 0), 0.12, 0.36, rnd_col(rng, PACK), 'gloss', 10, r_top=0.05)
    elif trade == 'office':
        shell(m, W, D, (0.82, 0.84, 0.86), (0.4, 0.42, 0.45), 'carpet', 'panels')
        # counter with a glass partition (check cashing / bail bonds)
        z = D * 0.55
        counter(m, F.sub(W / 2, 0, z, 0), W - 0.6, 0.6, 1.05, (0.5, 0.48, 0.45), (0.7, 0.7, 0.68), False)
        for x in np.arange(0.3, W - 0.25, 1.2):
            box(m, F.sub(x, 1.07, z), (0, 0.55, 0), (0.04, 1.1, 0.04), (0.6, 0.62, 0.65), 'metal', (0.8, 0.95))
        box(m, F.sub(W / 2, 2.17, z), (0, 0, 0), (W - 0.6, 0.05, 0.05), (0.6, 0.62, 0.65), 'metal', (0.9, 0.95))
        for x in np.arange(1.0, W - 0.8, 1.4):
            box(m, F.sub(x, 0, z + 1.0), (0, 0.38, 0), (1.2, 0.76, 0.7), (0.4, 0.28, 0.18), 'wood')
            box(m, F.sub(x, 0.95, z + 0.9), (0, 0, 0), (0.45, 0.3, 0.03), (0.05, 0.05, 0.05), 'gloss')
            box(m, F.sub(x, 0.95, z + 0.88), (0, 0, 0), (0.4, 0.25, 0.005), (0.3, 0.5, 0.9), 'screen', (1, 1))
        for x in np.arange(0.8, W - 0.5, 0.6):
            if clear(x, 0.9):
                chair(m, F.sub(x, 0, 0.9, math.pi), (0.2, 0.22, 0.26))
        for x in np.arange(0.8, W - 0.5, 1.0):
            frame_art(m, F.sub(x, 1.9, backz - 0.02, math.pi), 0.5, 0.7, rng)
    elif trade in ('lobby', 'lobby_white', 'lobby_dark', 'cn_herbs'):
        wall = {'lobby': (0.55, 0.38, 0.24), 'lobby_white': (0.92, 0.9, 0.86), 'lobby_dark': (0.3, 0.28, 0.27), 'cn_herbs': (0.45, 0.28, 0.15)}[trade]
        shell(m, W, D, wall, (0.6, 0.55, 0.5), 'terrazzo', 'none' if trade != 'lobby_white' else 'panels', (0.7, 0.65, 0.6))
        if trade == 'cn_herbs':
            # wall of small herb drawers
            for x in np.arange(0.3, W - 0.2, 0.32):
                for y in np.arange(0.3, 2.4, 0.28):
                    box(m, F.sub(x, y, backz - 0.15), (0, 0, 0), (0.3, 0.26, 0.3), (0.45, 0.28, 0.14), 'wood', (0.6, 0.85))
                    box(m, F.sub(x, y, backz - 0.3), (0, 0, 0), (0.04, 0.03, 0.02), (0.7, 0.6, 0.3), 'metal')
            counter(m, F.sub(W / 2, 0, D * 0.5, 0), W - 1.2, 0.6, 0.95, (0.4, 0.25, 0.12), (0.3, 0.18, 0.08), True, True, rng)
            for x in np.arange(1.0, W - 0.5, 1.5):
                lantern(m, F.sub(x, H, D * 0.3))
        else:
            counter(m, F.sub(W * 0.65, 0, D * 0.6, 0), min(2.4, W * 0.4), 0.6, 1.05, (0.35, 0.22, 0.12), (0.2, 0.12, 0.07), False)
            if trade == 'lobby_dark':
                for x in np.arange(0.8, W - 0.5, 1.2):
                    box(m, F.sub(x, 1.1, backz - 0.03), (0, 0, 0), (1.0, 2.2, 0.04), (0.45, 0.45, 0.47), 'metal')
            else:
                box(m, F.sub(W * 0.65, 1.7, backz - 0.03), (0, 0, 0), (1.2, 0.8, 0.04), (0.35, 0.22, 0.12), 'wood')
            for k, x in enumerate((0.8, 1.6)):
                f = F.sub(x, 0, D * 0.4, math.pi / 2)
                box(m, f, (0, 0.22, 0), (0.8, 0.44, 0.8), (0.4, 0.12, 0.08), 'fabric', (0.5, 0.85))
                box(m, f, (0, 0.6, -0.35), (0.8, 0.5, 0.15), (0.4, 0.12, 0.08), 'fabric', (0.6, 0.9))
            plant(m, F.sub(W - 0.5, 0, 0.8))
            for x in np.arange(1.0, W - 0.5, 1.8):
                lamp_pendant(m, F.sub(x, H, D * 0.45))
    else:
        shell(m, W, D, (0.8, 0.8, 0.78), (0.5, 0.5, 0.5), 'tile', 'panels')
        counter(m, F.sub(W / 2, 0, D * 0.6, 0), W - 1.0, 0.6, 1.0, (0.3, 0.3, 0.32), (0.6, 0.6, 0.6))


# ----------------------------------------------------------------------------------------------- rooms
def merge_rooms(raw):
    rooms = []
    for r in raw:
        if all(abs(p[4] - 0.9) < 0.03 for p in r['panes']):
            continue   # transoms above building doors: no room behind them
        o = np.array(r['o'])
        right = np.array(r['right']); right /= np.linalg.norm(right)
        n = np.array(r['n']); n /= np.linalg.norm(n)
        hit = None
        for q in rooms:
            if q['type'] != r['type'] or np.dot(q['right'], right) < 0.99:
                continue
            d = o - q['o']
            if abs(np.dot(d, right)) < 0.6 and abs(np.dot(d, n)) < 0.6 and abs(d[1]) < 0.6:
                hit = q
                break
        if hit:
            hit['panes'] += r['panes']
            hit['W'] = max(hit['W'], r['W']); hit['D'] = max(hit['D'], r['D'])
            # the window pane's frame is the reference (the door is recessed a little)
            if any(abs(p[4] - 0.5) < 0.03 for p in r['panes']):
                hit['o'] = o
        else:
            rooms.append({'o': o, 'right': right, 'n': n, 'W': r['W'], 'D': r['D'], 'type': r['type'], 'lit': r['lit'],
                          'panes': list(r['panes'])})
    return rooms


def main():
    raw = json.load(open(os.path.join(ROOT, 'data/shop_rooms.json')))
    rooms = merge_rooms(raw)
    gltf = gl.GLTF2(asset=gl.Asset(version='2.0'), scenes=[gl.Scene(nodes=[])], scene=0)
    blob = bytearray()
    meta = []
    for ri, r in enumerate(rooms):
        trade = TYPES.get(min(r['type'], 27), 'shop')
        rng = random.Random(ri * 7919 + r['type'])
        W = float(r['W']); D = min(float(r['D']), DMAX)
        m = Mesh()
        furnish(m, trade, W, D, rng, r['panes'])
        if not m.V:
            continue
        right = r['right']; up = np.array([0.0, 1.0, 0.0]); inward = -r['n']
        Rm = np.stack([right, up, inward], axis=1)
        V = np.array(m.V, np.float32) @ Rm.T.astype(np.float32) + r['o'].astype(np.float32)
        N = np.array(m.N, np.float32) @ Rm.T.astype(np.float32)
        N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-6)
        C = np.array(m.C, np.float32)
        U = np.array(m.U, np.float32)
        U2 = np.array(m.U2, np.float32)
        I = np.array(m.I, np.uint32).reshape(-1, 3)
        # glTF front faces are counter-clockwise: orient every triangle by its vertex normal (the room frame is mirrored)
        g = np.cross(V[I[:, 1]] - V[I[:, 0]], V[I[:, 2]] - V[I[:, 0]])
        flip = np.einsum('ij,ij->i', g, N[I[:, 0]]) < 0
        I[flip] = I[flip][:, [0, 2, 1]]
        I = I.reshape(-1)
        acc = {}
        for name, arr, tp in (('POSITION', V, gl.VEC3), ('NORMAL', N, gl.VEC3), ('COLOR_0', C, gl.VEC4), ('TEXCOORD_0', U, gl.VEC2), ('TEXCOORD_1', U2, gl.VEC2)):
            off = len(blob)
            data = arr.astype(np.float32).tobytes()
            blob += data
            while len(blob) % 4:
                blob += b'\0'
            gltf.bufferViews.append(gl.BufferView(buffer=0, byteOffset=off, byteLength=len(data), target=gl.ARRAY_BUFFER))
            a = gl.Accessor(bufferView=len(gltf.bufferViews) - 1, componentType=gl.FLOAT, count=len(arr), type=tp)
            if name == 'POSITION':
                a.min = V.min(0).tolist(); a.max = V.max(0).tolist()
            gltf.accessors.append(a)
            acc[name] = len(gltf.accessors) - 1
        off = len(blob)
        data = I.tobytes()
        blob += data
        while len(blob) % 4:
            blob += b'\0'
        gltf.bufferViews.append(gl.BufferView(buffer=0, byteOffset=off, byteLength=len(data), target=gl.ELEMENT_ARRAY_BUFFER))
        gltf.accessors.append(gl.Accessor(bufferView=len(gltf.bufferViews) - 1, componentType=gl.UNSIGNED_INT, count=len(I), type=gl.SCALAR))
        prim = gl.Primitive(attributes=gl.Attributes(**acc), indices=len(gltf.accessors) - 1)
        gltf.meshes.append(gl.Mesh(name='room_%d' % ri, primitives=[prim]))
        gltf.nodes.append(gl.Node(name='room_%d' % ri, mesh=len(gltf.meshes) - 1))
        gltf.scenes[0].nodes.append(len(gltf.nodes) - 1)
        lamp = LAMP.get(trade, (1, 0.95, 0.85))
        c = (r['o'] + right * W / 2 + inward * D / 2 + up * H / 2)
        meta.append({'node': 'room_%d' % ri, 'trade': trade, 'type': min(int(r['type']), 26), 'lit': r['lit'],
                     'front': r['o'].tolist(), 'in': inward.tolist(), 'centre': c.tolist(),
                     'size': [W, H, D], 'tris': len(I) // 3})
    gltf.buffers.append(gl.Buffer(byteLength=len(blob)))
    gltf.set_binary_blob(bytes(blob))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    gltf.save_binary(OUT)
    json.dump(meta, open(os.path.join(ROOT, 'data/shop_interiors.json'), 'w'), indent=1)
    from collections import Counter
    print('rooms', len(meta), 'tris', sum(x['tris'] for x in meta), Counter(x['trade'] for x in meta))


if __name__ == '__main__':
    main()
