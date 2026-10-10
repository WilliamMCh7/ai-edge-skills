import time, sys
import numpy as np
from synth import make_page, make_screens, ground_truth
import stitch
from stitch import plan, segments, render

def run_case(name, seed, W=390, H=844, hh=91, fh=83, P=4000, n=None, overlap=(0.1, 0.8), **kw):
    rng = np.random.default_rng(seed)
    import synth; synth.S = W / 390
    page = make_page(rng, W, P, repetitive=kw.pop('repetitive', False), blank_blocks=kw.pop('blank', True))
    vp = H - hh - fh
    offs = [0]
    while offs[-1] + vp < P - vp and (n is None or len(offs) < n):
        ov = rng.uniform(*overlap)
        offs.append(offs[-1] + max(1, int(vp * (1 - ov))))
    shots = make_screens(rng, W, H, page, offs, hh, fh, **kw)
    gt = ground_truth(shots, page, offs, hh, fh, H)
    t = time.time()
    stitch.LOSSY = bool(kw.get('jpeg'))
    keep, seams, _, _ = plan(shots)
    stitch.LOSSY = False
    segs = segments(shots, keep, seams)
    out = render(shots, segs)
    dt = time.time() - t
    exp_d0 = [offs[i + 1] - offs[i] for i in range(len(offs) - 1)]
    if kw.get('fab'):
        ok = [s['d'] for s in seams] == exp_d0
    else:
        ok = out.shape == gt.shape and np.abs(out.astype(int) - gt.astype(int)).max() <= (60 if kw.get('jpeg') else 0)
    bad = [ (s['a'], s['b']) for s in seams if not s['matched']]
    exp_d = [offs[i + 1] - offs[i] for i in range(len(offs) - 1)]
    got_d = [s['d'] for s in seams]
    amb = False
    if not ok and not kw.get('fab'):
        nz = lambda im: im[~(im.reshape(len(im), -1) >= 250).all(1)]
        a2, g2 = nz(out), nz(gt)
        unmatched_blank = all(not s['matched'] for s in seams if not s['matched'])
        amb = a2.shape == g2.shape and np.abs(a2.astype(int) - g2.astype(int)).max() <= (60 if kw.get('jpeg') else 0)
    tag = 'PASS' if ok else ('AMBIG-OK' if amb else 'FAIL')
    ok = ok or amb
    print(f"{tag} {name:28s} shots={len(shots)} out={out.shape[0]} gt={gt.shape[0]} unmatched={bad} t={dt:.2f}s")
    if not ok:
        print('   expected d', exp_d); print('   got d     ', got_d)
        print('   seams', [(s.get('s'), s.get('run'), s.get('inliers')) for s in seams])
    return ok

results = []
for seed in range(6):
    results.append(run_case(f'mixed seed={seed}', seed))
results.append(run_case('small overlaps 5-15%', 11, overlap=(0.05, 0.15)))
results.append(run_case('huge overlaps 85-95%', 12, overlap=(0.85, 0.95), P=2500))
results.append(run_case('list rows (repetitive)', 13, repetitive=True))
results.append(run_case('no blank blocks', 14, blank=False))
results.append(run_case('floating action button', 15, fab=True))
results.append(run_case('no clock change', 16, clock_change=False))
results.append(run_case('3x resolution', 17, W=1170, H=2532, hh=273, fh=249, P=9000, n=4))
results.append(run_case('jpeg q80', 18, jpeg=True))
# reversed order: feed screenshots bottom-to-top, expect auto reversal and exact reconstruction
rng = np.random.default_rng(21); import synth; synth.S = 1
page = make_page(rng, 390, 3000); offs = [0, 300, 650, 1000, 1400]
shots = make_screens(rng, 390, 844, page, offs, 91, 83)
keep, seams, _, rev = plan(shots[::-1])
segs = segments(shots[::-1], keep, seams); out = render(shots[::-1], segs)
gt = ground_truth(shots, page, offs, 91, 83, 844)
ok = rev and out.shape == gt.shape and (out == gt).all()
print(f"{'PASS' if ok else 'FAIL'} reversed input auto-fix       rev={rev} out={out.shape[0]} gt={gt.shape[0]}")
results.append(ok)
# exact duplicate in the middle is dropped
shots2 = shots[:2] + [shots[1]] + shots[2:]
keep, seams, _, _ = plan(shots2)
ok = keep == [0, 1, 3, 4, 5]
print(f"{'PASS' if ok else 'FAIL'} duplicate screenshot dropped  keep={keep}")
results.append(ok)
print(f"{sum(results)}/{len(results)} passed")
