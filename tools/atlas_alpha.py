"""Give the door decals of the vehicle atlas a real alpha channel.

The OCPD and AMBULANCE panels were painted on a flat off-white card, which showed on the cars as a white sticker
lighter than the door paint. Here the card colour becomes transparent (with antialiased edges un-blended from it),
so in vehicle.gdshader only the lettering, star and stripes are printed on the paint. Plates and the taxi sign stay
opaque (they are real plates and a lit sign).
"""
import os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = os.path.join(ROOT, 'assets/textures/vehicles/vehicle_atlas.png')
SRC = os.path.join(ROOT, 'tools/vehicle_atlas_src.png')
if not os.path.exists(SRC):
    Image.open(P).convert('RGB').save(SRC)
im = np.asarray(Image.open(SRC).convert('RGB')).astype(np.float32) / 255.0
h, w, _ = im.shape
alpha = np.ones((h, w), np.float32)
out = im.copy()
for (y0, y1, bg) in [(320, 576, (236, 236, 236)), (576, 726, (240, 240, 236))]:
    bgc = np.array(bg, np.float32) / 255.0
    reg = im[y0:y1]
    d = np.abs(reg - bgc).max(axis=2)
    a = np.clip(d / 0.18, 0.0, 1.0)
    a = a * a * (3 - 2 * a)
    # un-blend: colour = bg + (c - bg) / a
    safe = np.maximum(a, 1e-3)[..., None]
    col = np.clip(bgc + (reg - bgc) / safe, 0.0, 1.0)
    out[y0:y1] = np.where(a[..., None] > 0.01, col, reg)
    alpha[y0:y1] = a
rgba = np.dstack([out, alpha])
Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), 'RGBA').save(P)
print('ok', P)
