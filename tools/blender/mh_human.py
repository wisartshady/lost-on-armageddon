"""MakeHuman (CC0 assets) without MakeHuman: base mesh + targets + rig weights + proxy fitting, in numpy.

Sources (all CC0): the MakeHuman 1.x repository data (base.obj, targets, default rig weights) and the MakeHuman
system asset pack (skins, hair, eyes, eyebrows, eyelashes), plus the "skins01" pack. Paths below.
MakeHuman space: y up, the human faces +z, its left is +x, units are decimetres.
"""
import os
import numpy as np

MH = '/home/claude/makehumancommunity/makehuman/makehuman/data'
SYS = '/home/claude/dl/mh/sys'


def load_obj(path):
    V, VT, F = [], [], []
    group = None
    for line in open(path, encoding='utf-8', errors='ignore'):
        if line.startswith('v '):
            V.append([float(x) for x in line.split()[1:4]])
        elif line.startswith('vt '):
            VT.append([float(x) for x in line.split()[1:3]])
        elif line.startswith('g '):
            group = line.split(maxsplit=1)[1].strip()
        elif line.startswith('f '):
            vs, ts = [], []
            for tok in line.split()[1:]:
                p = tok.split('/')
                vs.append(int(p[0]) - 1)
                ts.append(int(p[1]) - 1 if len(p) > 1 and p[1] else -1)
            F.append((vs, ts, group))
    return np.array(V, float), np.array(VT, float), F


def load_target(path):
    idx, d = [], []
    for line in open(path):
        if not line.strip() or line.startswith('#'):
            continue
        p = line.split()
        idx.append(int(p[0]))
        d.append([float(p[1]), float(p[2]), float(p[3])])
    return np.array(idx, int), np.array(d, float).reshape(-1, 3)


def human(targets):
    """targets: list of (path relative to data/targets, weight). Returns (V, VT, faces)."""
    V, VT, F = load_obj(os.path.join(MH, '3dobjs/base.obj'))
    for rel, w in targets:
        if w == 0:
            continue
        i, d = load_target(os.path.join(MH, 'targets', rel))
        V[i] += d * w
    return V, VT, F


def groups(F):
    out = {}
    for vs, ts, g in F:
        out.setdefault(g, set()).update(vs)
    return out


def joint(V, G, name):
    return V[sorted(G['joint-' + name])].mean(0)


def rig_weights():
    import json
    d = json.load(open(os.path.join(MH, 'rigs/default_weights.mhw')))['weights']
    return {b: (np.array([p[0] for p in v], int), np.array([p[1] for p in v], float)) for b, v in d.items()}


def fit_proxy(mhclo, V):
    """Fitted vertex positions of a proxy (hair, eyes, eyebrows, eyelashes) on the morphed base mesh V."""
    base = os.path.dirname(mhclo)
    scales = {}
    refs = []
    obj = None
    in_verts = False
    for line in open(mhclo, encoding='utf-8', errors='ignore'):
        s = line.strip()
        if not s or s.startswith('#'):
            continue
        p = s.split()
        if p[0] == 'obj_file':
            obj = p[1]
        elif p[0] in ('x_scale', 'y_scale', 'z_scale'):
            scales[p[0][0]] = (int(p[1]), int(p[2]), float(p[3]))
        elif p[0] == 'verts':
            in_verts = True
        elif in_verts:
            if p[0][0].isalpha():
                in_verts = False
                continue
            if len(p) == 1:
                refs.append(([int(p[0])], [1.0], [0.0, 0.0, 0.0]))
            elif len(p) >= 9:
                refs.append(([int(p[0]), int(p[1]), int(p[2])], [float(p[3]), float(p[4]), float(p[5])],
                             [float(p[6]), float(p[7]), float(p[8])]))
    sc = []
    for ax, k in (('x', 0), ('y', 1), ('z', 2)):
        if ax in scales:
            a, b, dist = scales[ax]
            sc.append(abs(V[a][k] - V[b][k]) / dist)
        else:
            sc.append(1.0)
    sc = np.array(sc)
    P = np.array([sum(w * V[i] for i, w in zip(ix, ws)) + np.array(off) * sc for ix, ws, off in refs])
    PV, PT, PF = load_obj(os.path.join(base, obj))
    return P, PT, PF
