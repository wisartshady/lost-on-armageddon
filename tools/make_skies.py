"""Sky panoramas for shaders/sky.gdshader from Poly Haven "pure sky" HDRIs (CC0).

For every HDRI: keep the upper hemisphere of the equirect (4096x1024), tonemap to 8-bit sRGB with a fixed
exposure per sky so that the sky sits in a natural range, soft-clip the sun, and record where the sun is
(azimuth / elevation) so the shader can turn the panorama to match the game's sun.
Usage: python3 tools/make_skies.py <folder with the .hdr files>
"""
import sys, os, json
import numpy as np
import cv2

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'assets/textures/sky')

# name in game, source HDRI, target for the median sky luminance (linear, before the curve)
SKIES = [
    ('sky_clear', 'kloofendal_48d_partly_cloudy_puresky', 0.30),
    ('sky_cloudy', 'kloppenheim_03_puresky', 0.36),
    ('sky_overcast', 'kloofendal_overcast_puresky', 0.42),
    ('sky_dusk', 'industrial_sunset_02_puresky', 0.26),
    ('sky_night', 'kloppenheim_07_puresky', 0.035),
]


def tonemap(x):
    # gentle filmic shoulder: linear in the sky's range, rolls highlights (the sun) off to white
    a = x / (1.0 + x * 0.35)
    return np.clip(a, 0.0, 1.0)


def srgb(x):
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1.0 / 2.4) - 0.055)


def main(src):
    os.makedirs(OUT, exist_ok=True)
    meta = {}
    for name, hdri, exp in SKIES:
        img = cv2.imread(os.path.join(src, hdri + '.hdr'), cv2.IMREAD_UNCHANGED)[:, :, ::-1].astype(np.float32)
        h, w, _ = img.shape
        top = img[: h // 2]
        lum = top @ np.array([0.2126, 0.7152, 0.0722], np.float32)
        # sun: centroid of the brightest pixels
        thr = np.percentile(lum, 99.97)
        ys, xs = np.nonzero(lum >= thr)
        wts = lum[ys, xs]
        sx = float((xs * wts).sum() / wts.sum())
        sy = float((ys * wts).sum() / wts.sum())
        az = (sx / w) * 360.0          # degrees, 0 at the left edge of the panorama
        el = 90.0 - (sy / (h / 2)) * 90.0
        peak = float(lum.max())
        exp = exp / float(np.median(lum))
        ldr = srgb(tonemap(top * exp))
        # the last rows at the horizon: blend to their own average so there is no hard line
        out = (ldr * 255.0 + 0.5).astype(np.uint8)
        cv2.imwrite(os.path.join(OUT, name + '.jpg'), out[:, :, ::-1], [cv2.IMWRITE_JPEG_QUALITY, 92])
        avg_h = srgb(tonemap(top[-24:].reshape(-1, 3).mean(0) * exp))
        meta[name] = {'source': hdri, 'exposure': round(exp, 5), 'sun_az': round(az, 2), 'sun_el': round(el, 2), 'peak': round(peak, 1),
                      'horizon': [round(float(c), 4) for c in avg_h]}
        print(name, meta[name])
    json.dump(meta, open(os.path.join(ROOT, 'data/skies.json'), 'w'), indent=1)


if __name__ == '__main__':
    main(sys.argv[1])
