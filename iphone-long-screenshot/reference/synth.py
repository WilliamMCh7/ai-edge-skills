"""Synthetic iPhone-like screenshot generator (grayscale-ish RGB uint8)."""
import numpy as np
from PIL import Image, ImageDraw, ImageFont
ALPHA = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
S = 1.0
_fonts = {}
def draw_text(page, x, y, text, color, W):
    size = int(15 * S)
    f = _fonts.get(size) or _fonts.setdefault(size, ImageFont.load_default(size=size))
    h = int(20 * S)
    tile = Image.fromarray(page[y:y + h].copy())
    ImageDraw.Draw(tile).text((x, 0), text, fill=(color, color, color), font=f)
    page[y:y + h] = np.array(tile)

def make_page(rng, W, P, repetitive=False, blank_blocks=True):
    page = np.full((P, W, 3), 255, np.uint8)
    y = 10
    row_tpl = None
    while y < P - 40:
        kind = rng.choice(['text', 'text', 'text', 'card', 'image', 'sep', 'blank'] if blank_blocks else ['text', 'text', 'card', 'image', 'sep'])
        if repetitive:
            kind = 'listrow'
        if kind == 'text':
            n = rng.integers(1, 6)
            for _ in range(n):
                if y + 24 >= P:
                    break
                words = ' '.join(''.join(rng.choice(list(ALPHA), rng.integers(2, 9))) for _ in range(rng.integers(2, 9)))
                draw_text(page, 16, y, words, int(rng.integers(20, 90)), W)
                y += int(22 * S)
            y += 10
        elif kind == 'card':
            h = rng.integers(60, 180)
            page[y:y + h, 12:W - 12] = 242
            page[y + 10:y + 22, 24:24 + rng.integers(60, W - 60)] = 40
            page[y + 30:y + 40, 24:24 + rng.integers(40, W - 60)] = 120
            y += h + 12
        elif kind == 'image':
            h = int(min(rng.integers(80, 220), P - y - 2))
            blk = rng.integers(0, 255, (h // 8 + 1, (W - 24) // 8 + 1, 3)).astype(np.uint8)
            blk = np.kron(blk, np.ones((8, 8, 1), np.uint8))[:h, :W - 24]
            page[y:y + h, 12:W - 12] = blk
            y += h + 12
        elif kind == 'sep':
            page[y:y + 1, 16:] = 200
            y += 12
        elif kind == 'blank':
            y += rng.integers(100, 320)
        elif kind == 'listrow':
            if row_tpl is None:
                row_tpl = np.full((70, W, 3), 255, np.uint8)
                row_tpl[15:55, 16:56] = (0, 120, 255)  # avatar
                row_tpl[69:70, 72:] = 210  # separator
            page[y:y + 70] = row_tpl
            # different text per row (like real lists) unless exact repeats wanted
            tw = rng.integers(60, W - 100)
            page[y + 18:y + 30, 72:72 + tw] = 30
            page[y + 38:y + 48, 72:72 + rng.integers(40, W - 120)] = 140
            y += 70
    return page

def make_screens(rng, W, H, page, offsets, header_h, footer_h, clock_change=True, fab=False, jpeg=False):
    vp = H - header_h - footer_h
    shots = []
    for k, o in enumerate(offsets):
        s = np.full((H, W, 3), 255, np.uint8)
        s[header_h:header_h + vp] = page[o:o + vp]
        # header: status bar + nav bar
        s[:header_h] = 248
        s[header_h - 1:header_h] = 200
        clock_w = 30 + (k * 7 % 20 if clock_change else 0)
        sb = max(4, header_h // 4)
        s[sb:sb + max(3, header_h // 7), 20:20 + clock_w] = 10  # clock changes
        s[sb:sb + max(3, header_h // 7), W - 50:W - 20] = 10  # battery
        s[header_h // 2 + 2:header_h // 2 + 2 + max(3, header_h // 6), W // 2 - 40:W // 2 + 40] = 0  # title
        # footer: tab bar
        s[H - footer_h:] = 248
        s[H - footer_h:H - footer_h + 1] = 200
        for i in range(4):
            cx = int(W * (i + 0.5) / 4)
            s[H - footer_h + 8:H - footer_h + 8 + footer_h // 3, cx - 10:cx + 10] = 100 if i else 0
        s[H - 8:H - 5, W // 2 - 60:W // 2 + 60] = 0  # home indicator
        if fab:
            s[H - footer_h - 70:H - footer_h - 14, W - 72:W - 16] = (255, 60, 60)
        shots.append(s)
    if jpeg:
        from PIL import Image
        import io
        out = []
        for s in shots:
            b = io.BytesIO(); Image.fromarray(s).save(b, 'JPEG', quality=80); b.seek(0)
            out.append(np.array(Image.open(b).convert('RGB')))
        shots = out
    return shots

def ground_truth(shots, page, offsets, header_h, footer_h, H):
    vp = H - header_h - footer_h
    top = shots[0][:header_h]
    body = page[offsets[0]:offsets[-1] + vp]
    bot = shots[-1][H - footer_h:]
    return np.concatenate([top, body, bot], 0)
