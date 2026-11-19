"""Footsteps on metal that do not ring like a bell.

Builds three step sets from the recorded concrete steps (assets/audio/steps2/concrete_XX.wav):
  carroof  - painted sheet steel with a glued headliner under it: a dull hollow "thunk", every mode dies in < 0.2 s
  manhole  - a heavy cast-iron lid in its frame: almost a concrete step, with a short low clunk of the lid seating
  metal    - other thick steel (dumpster lids, plates): heavier dull knock
Each shoe impact excites a small set of strongly damped modes; nothing is left to sustain above ~700 Hz.
Writes <kind>_NN.wav (44.1 kHz mono 16 bit) and updates data/steps.json.
"""
import json, os, wave, glob
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(ROOT, 'assets/audio/steps2')
SR = 44100
rng = np.random.default_rng(2411)


def load(path):
    with wave.open(path) as w:
        a = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0
    return a


def save(path, a):
    a = np.clip(a, -1, 1)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((a * 32767).astype(np.int16).tobytes())


def onepole_lp(a, fc):
    k = np.exp(-2 * np.pi * fc / SR)
    out = np.zeros_like(a)
    y = 0.0
    for i, x in enumerate(a):
        y = (1 - k) * x + k * y
        out[i] = y
    return out


def hp(a, fc):
    return a - onepole_lp(a, fc)


def modes(freqs, taus, amps, n):
    t = np.arange(n) / SR
    ir = np.zeros(n, np.float32)
    for f, tau, g in zip(freqs, taus, amps):
        ph = rng.uniform(0, 2 * np.pi)
        ir += g * np.sin(2 * np.pi * f * t + ph) * np.exp(-t / tau)
    return ir


def level(x, ref, ratio):
    """scale x so its RMS over the first 120 ms is ratio * that of ref"""
    m = int(0.12 * SR)
    return x * ratio * np.sqrt(np.mean(ref[:m] ** 2)) / (np.sqrt(np.mean(x[:m] ** 2)) + 1e-9)


def excitation(step):
    # the heel/toe impacts of the recorded step: a rectified, smoothed envelope with its fine noise
    env = onepole_lp(np.abs(step), 900.0)
    return env * 2.0


def build(kind, step):
    n = len(step) + int(0.25 * SR)
    s = np.zeros(n, np.float32)
    s[:len(step)] = step
    ex = np.zeros(n, np.float32)
    ex[:len(step)] = excitation(step)
    det = rng.uniform(0.93, 1.07)
    if kind == 'carroof':
        f = np.array([62, 104, 151, 209, 287, 392, 540]) * det
        tau = [0.15, 0.11, 0.085, 0.06, 0.045, 0.03, 0.02]
        g = [1.0, 0.85, 0.6, 0.42, 0.28, 0.16, 0.08]
        body = np.convolve(ex, modes(f, tau, g, int(0.3 * SR)))[:n]
        dry = onepole_lp(s, 2600.0)            # the shoe on painted steel: softer top end than concrete
        out = dry + level(body, dry, 0.75)
    elif kind == 'manhole':
        f = np.array([96, 238, 455, 690]) * det
        tau = [0.05, 0.03, 0.018, 0.012]
        g = [1.0, 0.45, 0.22, 0.1]
        body = np.convolve(ex, modes(f, tau, g, int(0.15 * SR)))[:n]
        out = s + level(body, s, 0.35)
        out = onepole_lp(out, 5200.0)
    else:  # metal
        f = np.array([88, 141, 214, 318, 470]) * det
        tau = [0.09, 0.07, 0.05, 0.035, 0.022]
        g = [1.0, 0.7, 0.45, 0.25, 0.12]
        body = np.convolve(ex, modes(f, tau, g, int(0.25 * SR)))[:n]
        dry = onepole_lp(s, 3200.0)
        out = dry + level(body, dry, 0.6)
    out = hp(out, 35.0)
    # match the loudness of the recorded concrete step so the mix stays as it was
    pk = np.max(np.abs(step)) + 1e-6
    out *= pk / (np.max(np.abs(out)) + 1e-6)
    # trim the silent tail
    thr = pk * 0.004
    idx = np.nonzero(np.abs(out) > thr)[0]
    end = min(len(out), (idx[-1] if len(idx) else len(out)) + int(0.02 * SR))
    out = out[:end]
    fade = min(int(0.015 * SR), len(out))
    out[-fade:] *= np.linspace(1, 0, fade)
    return out


def main():
    steps = sorted(glob.glob(os.path.join(DIR, 'concrete_*.wav')))
    info_path = os.path.join(ROOT, 'data/steps.json')
    info = json.load(open(info_path))
    for kind in ('carroof', 'manhole', 'metal'):
        for i, p in enumerate(steps[:12]):
            save(os.path.join(DIR, '%s_%02d.wav' % (kind, i)), build(kind, load(p)))
        info[kind] = {'count': 12}
    json.dump(info, open(info_path, 'w'), indent=1)
    print('ok')


if __name__ == '__main__':
    main()
