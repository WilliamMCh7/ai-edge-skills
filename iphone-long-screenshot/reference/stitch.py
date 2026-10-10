"""Reference implementation of the Captura Larga stitching algorithm (mirrors Swift)."""
import numpy as np

BINS = None          # column bins per row signature; None -> clamp(W // 12, 48, 128)
STRICT = (0.75, 3.0) # (mean, max) per-bin tolerance for lossless screenshots (PNG)
LOOSE = (3.5, 14.0)  # fallback tolerance for recompressed (JPEG) screenshots
TOL = STRICT
SAMPLE_ROWS = 400    # key rows of B sampled for the coarse offset search
TOP_CANDIDATES = 24  # offsets re-scored with the full run analysis
MIN_INLIERS = 5      # key-row inliers needed inside the overlap run
RUN_GAP = 6          # mismatching rows tolerated inside an overlap run
DUP_RATIO = 0.97     # fraction of key rows equal at d=0 to call a duplicate

def signatures(img):
    g = img.astype(np.float32) @ np.array([0.299, 0.587, 0.114], np.float32)
    H, W = g.shape
    bins = BINS or min(128, max(48, W // 12))
    edges = np.linspace(0, W, bins + 1).astype(int)
    return np.stack([g[:, edges[i]:max(edges[i + 1], edges[i] + 1)].mean(1) for i in range(bins)], 1)

def rows_match(a, b):
    d = np.abs(a - b)
    return (d.mean(-1) <= TOL[0]) & (d.max(-1) <= TOL[1])

def change_rows(sig):
    """Key-row candidates: rows that differ from the row above (edges / textured rows). Rows inside
    solid blocks repeat their neighbour and would create spurious matches at small shifts."""
    ch = np.zeros(len(sig), bool)
    ch[1:] = ~rows_match(sig[1:], sig[:-1])
    return ch

def static_rows(sa, sb):
    n = min(len(sa), len(sb))
    st = np.zeros(len(sb), bool)
    st[:n] = rows_match(sa[:n], sb[:n])
    return st

def coarse_offsets(sa, sb, keys, static_a):
    """Rank offsets by inliers - 2*outliers over sampled key rows of B, ignoring rows that land on
    fixed bars of A (static rows). Returns the TOP_CANDIDATES best offsets."""
    HA = len(sa)
    idx = np.nonzero(keys)[0]
    if len(idx) == 0:
        return []
    if len(idx) > SAMPLE_ROWS:
        idx = idx[np.linspace(0, len(idx) - 1, SAMPLE_ROWS).astype(int)]
    scores = []
    for d in range(-(HA - 1), HA):
        if d == 0:
            continue
        ys = idx[(idx + d >= 0) & (idx + d < HA)]
        ys = ys[~static_a[ys + d]]
        if len(ys) == 0:
            continue
        n_in = int(rows_match(sa[ys + d], sb[ys]).sum())
        if n_in:
            n_out = len(ys) - n_in
            scores.append((n_in - 2 * n_out, n_in, -abs(d), d))
    scores.sort(reverse=True)
    return [x[3] for x in scores[:TOP_CANDIDATES]]

def overlap_run(sa, sb, keys, d):
    """Best gap-tolerant run of B rows y with A[y+d] ~ B[y]; scored by key-row inliers."""
    HA, HB = len(sa), len(sb)
    y_lo, y_hi = max(0, -d), min(HB, HA - d)
    if y_hi <= y_lo:
        return None
    m = rows_match(sa[y_lo + d:y_hi + d], sb[y_lo:y_hi])
    best = None
    def close(s, e):
        nonlocal best
        inl = int((m[s - y_lo:e - y_lo] & keys[s:e]).sum())
        if best is None or (inl, e - s) > (best[2], best[1] - best[0]):
            best = (s, e, inl)
    start = last_ok = None; gap = 0
    for i, ok in enumerate(m):
        y = y_lo + i
        if ok:
            if start is None: start = y
            last_ok, gap = y, 0
        elif start is not None:
            gap += 1
            if gap > RUN_GAP:
                close(start, last_ok + 1); start = None; gap = 0
    if start is not None:
        close(start, last_ok + 1)
    return best

def static_bars(sa, sb):
    n = min(len(sa), len(sb)); lim = int(n * 0.4)
    def prefix(eq):
        best = cum = 0
        for i, e in enumerate(eq):
            cum += e
            if e and cum / (i + 1) >= 0.75: best = i + 1
        return best
    top = prefix(rows_match(sa[:lim], sb[:lim]))
    bot = prefix(rows_match(sa[::-1][:lim], sb[::-1][:lim]))
    return top, bot

LOOSE_MAX_COST = 3.0
LOOSE_MARGIN = 0.6       # winner cost must be < LOOSE_MARGIN * runner-up cost (|d - d2| > 8)
LOOSE_MIN_SUPPORT = 12   # key rows needed to evaluate an offset in lossy mode

LOSSY = False            # set from the source format (JPEG/HEIC); PNG screenshots are lossless

def match_pair(sa, sb):
    """Lossless sources: strict inlier matching. Lossy sources: cost-based matching."""
    global TOL
    TOL = STRICT
    if LOSSY:
        return _match_pair_lossy(sa, sb)
    return _match_pair(sa, sb)

def _match_pair_lossy(sa, sb):
    global TOL
    TOL = LOOSE
    try:
        HA = len(sa)
        stat = static_rows(sa, sb)
        static_a = np.zeros(HA, bool); n = min(HA, len(sb)); static_a[:n] = stat[:n]
        TOL = STRICT
        keys = change_rows(sb) & ~stat           # structural rows, detected strictly
        TOL = LOOSE
        idx = np.nonzero(keys)[0]
        if len(idx) > SAMPLE_ROWS:
            idx = idx[np.linspace(0, len(idx) - 1, SAMPLE_ROWS).astype(int)]
        costs = {}
        for d in range(-(HA - 1), HA):
            if d == 0:
                continue
            ys = idx[(idx + d >= 0) & (idx + d < HA)]
            ys = ys[~static_a[ys + d]]
            if len(ys) < LOOSE_MIN_SUPPORT:
                continue
            costs[d] = float(np.median(np.abs(sa[ys + d] - sb[ys]).mean(1)))
        if not costs:
            return None
        d1 = min(costs, key=lambda d: (costs[d], abs(d)))
        rivals = [c for d, c in costs.items() if abs(d - d1) > 8]
        c2 = min(rivals) if rivals else float('inf')
        if costs[d1] > LOOSE_MAX_COST or costs[d1] >= LOOSE_MARGIN * c2:
            return None
        run = overlap_run(sa, sb, keys, d1)
        if not run or run[2] < MIN_INLIERS:
            return None
        return (d1, run)
    finally:
        TOL = STRICT

def is_duplicate(a, b):
    global TOL
    if len(a) != len(b):
        return False
    try:
        for tol in (STRICT, LOOSE):
            TOL = tol
            keys = change_rows(b)
            if keys.sum() == 0 or (rows_match(a, b) & keys).sum() / keys.sum() >= DUP_RATIO:
                return True
        return False
    finally:
        TOL = STRICT

REFINE = 6           # +/- rows searched around the winning offset (sub-tolerance precision)

def _match_pair(sa, sb):
    stat = static_rows(sa, sb)          # same-position equal rows: fixed bars (symmetric for A and B)
    static_a = np.zeros(len(sa), bool); static_a[:min(len(sa), len(sb))] = stat[:min(len(sa), len(sb))]
    keys = change_rows(sb) & ~stat
    best = None
    for d in coarse_offsets(sa, sb, keys, static_a):
        run = overlap_run(sa, sb, keys, d)
        if run and run[2] >= MIN_INLIERS and (best is None or (run[2], -abs(d)) > (best[1][2], -abs(best[0]))):
            best = (d, run)
    if best is None:
        return None
    d, (y0, y1, _) = best
    def cost(dd):
        lo, hi = max(y0, -dd), min(y1, len(sa) - dd)
        if hi - lo < (y1 - y0) // 2:
            return float('inf')
        return float(np.abs(sa[lo + dd:hi + dd] - sb[lo:hi]).mean())
    d2 = min(range(d - REFINE, d + REFINE + 1), key=lambda dd: (cost(dd), abs(dd - d)))
    if d2 != d:
        run = overlap_run(sa, sb, keys, d2)
        if run and run[2] >= MIN_INLIERS:
            best = (d2, run)
    return best

def flat_run(sig, start, step, limit):
    """Rows of uniform colour starting at `start` going in `step` direction; returns (count, colour)."""
    n, colour = 0, None
    y = start
    while 0 <= y < len(sig) and n < limit:
        row = sig[y]
        if row.max() - row.min() > STRICT[1] * 2:
            break
        c = float(row.mean())
        if colour is None:
            colour = c
        elif abs(c - colour) > STRICT[1]:
            break
        n += 1; y += step
    return n, colour

def plan(images, _allow_reverse=True):
    """Returns (keep, seams, sigs[, auto_reversed]). If every seam says the next image sits ABOVE
    the previous one, the order is reversed automatically (once)."""
    keep, seams, sigs = _plan(images)
    if _allow_reverse and seams and all((not sm['matched']) and sm.get('reversed') for sm in seams):
        order = list(range(len(images)))[::-1]
        k2, s2, g2 = _plan([images[i] for i in order])
        remap = lambda i: order[i]
        k2 = [remap(i) for i in k2]
        for sm in s2:
            sm['a'], sm['b'] = remap(sm['a']), remap(sm['b'])
        if sum(sm['matched'] for sm in s2) > 0:
            return k2, s2, [sigs[i] for i in range(len(images))], True
    return keep, seams, sigs, False

def _plan(images):
    sigs = [signatures(im) for im in images]
    keep = [0]
    for i in range(1, len(images)):
        if is_duplicate(sigs[keep[-1]], sigs[i]):
            continue
        keep.append(i)
    seams = []
    for k in range(len(keep) - 1):
        ia, ib = keep[k], keep[k + 1]
        sa, sb = sigs[ia], sigs[ib]
        best = match_pair(sa, sb)
        if best and best[0] > 0:
            d, (y0, y1, inl) = best
            seams.append(dict(a=ia, b=ib, matched=True, d=d, s=(y0 + y1) // 2, run=(y0, y1), inliers=inl,
                              header=y0, footer=len(sa) - (y1 + d)))
        else:
            h, f = static_bars(sa, sb)
            endA, startB = len(sa) - f, h
            # Overlap that is pure blank space cannot be measured: avoid duplicating the shared blank.
            tail, ca = flat_run(sa, endA - 1, -1, endA - h)
            head, cb = flat_run(sb, startB, 1, len(sb) - f - startB)
            if tail and head and abs(ca - cb) <= STRICT[1]:
                startB += min(tail, head)
            seams.append(dict(a=ia, b=ib, matched=False, reversed=bool(best and best[0] < 0),
                              d=None, s=None, header=h, footer=f, endA=endA, startB=startB))
    return keep, seams, sigs

def segments(images, keep, seams, include_header=True, include_footer=True):
    if not seams:
        return [(keep[0], 0, len(images[keep[0]]))]
    header, footer = seams[0]['header'], seams[-1]['footer']
    starts = {keep[0]: 0 if include_header else header}; ends = {}
    for sm in seams:
        if sm['matched']:
            ends[sm['a']] = sm['s'] + sm['d']; starts[sm['b']] = sm['s']
        else:
            ends[sm['a']] = sm['endA']; starts[sm['b']] = sm['startB']
    last = keep[-1]
    ends[last] = len(images[last]) if include_footer else len(images[last]) - footer
    return [(i, starts[i], ends[i]) for i in keep]

def render(images, segs):
    return np.concatenate([images[i][s:e] for i, s, e in segs], 0)
