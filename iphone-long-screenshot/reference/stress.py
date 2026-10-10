import sys, numpy as np, synth
from synth import make_page, make_screens
import stitch as st
def build(seed, W=390, H=844, hh=91, fh=83, P=4000, overlap=(0.1,0.8), **kw):
    rng = np.random.default_rng(seed); synth.S = W/390
    page = make_page(rng, W, P, repetitive=kw.pop('repetitive', False), blank_blocks=kw.pop('blank', True))
    vp = H-hh-fh; offs=[0]
    while offs[-1]+vp < P-vp:
        ov = rng.uniform(*overlap); offs.append(offs[-1]+max(1,int(vp*(1-ov))))
    return make_screens(rng, W, H, page, offs, hh, fh, **kw), offs, (hh, fh)
tot = dict(right=0, wrong=0, unmatched_amb=0, unmatched_bad=0)
wrongs = []
cfgs = []
for seed in range(100, 130): cfgs.append((seed, {}))
for seed in range(200, 210): cfgs.append((seed, dict(repetitive=True)))
for seed in range(300, 310): cfgs.append((seed, dict(overlap=(0.03, 0.2))))
for seed in range(400, 408): cfgs.append((seed, dict(jpeg=True)))
for seed in range(500, 503): cfgs.append((seed, dict(W=1179, H=2556, hh=294, fh=249, P=9000)))
for seed, kw in cfgs:
    shots, offs, (hh, fh) = build(seed, **dict(kw))
    H = shots[0].shape[0]
    keep, seams, sigs, _ = st.plan(shots)
    for sm in seams:
        a, b = sm['a'], sm['b']; dt = offs[b] - offs[a]
        if sm['matched']:
            if sm['d'] == dt: tot['right'] += 1
            else: tot['wrong'] += 1; wrongs.append((seed, kw, a, b, dt, sm['d']))
        else:
            sb, sa = sigs[b], sigs[a]
            st.TOL = st.STRICT
            keys = st.change_rows(sb)
            nkeys = int(keys[hh:H - fh - dt].sum()) if dt < H - hh - fh else 0
            tot['unmatched_amb' if nkeys < 5 else 'unmatched_bad'] += 1
            if nkeys >= 5: wrongs.append(('UNMATCHED', seed, kw.get('jpeg', False), a, b, dt, nkeys))
print(tot)
for w in wrongs: print(w)
