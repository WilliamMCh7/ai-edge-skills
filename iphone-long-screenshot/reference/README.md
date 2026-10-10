# Stitching reference (Python)

This folder holds the validated **Python reference implementation** of the Captura Larga stitching
algorithm. It is not part of the app build; it exists to design, test and re-check the algorithm
quickly on synthetic data. The Swift code in `LongScreenshot/Stitching/` is a direct port and uses
the same constants and decisions (bins, STRICT/LOOSE tolerances, 400 sampled key rows, top 24
candidates, MIN_INLIERS 5, RUN_GAP 6, ±6 refinement, lossy cost thresholds, static bars, blank
merge, duplicate ratio 0.97, auto-reverse). If you change a constant or a decision here, change it in
Swift too (and vice versa).

| File | What it is |
| --- | --- |
| `stitch.py` | The algorithm: row signatures, pair matching (strict and lossy), static bars, blank merge, duplicate removal, auto-reverse, segments and rendering. |
| `synth.py` | Synthetic iPhone-like screenshots: a random page (text, cards, noise images, separators, blank space, list rows) cut into screenshots with a fixed status/navigation bar and tab bar, optional floating button and JPEG round-trip, plus the ground truth. `LongScreenshotTests/SyntheticScreens.swift` is its Swift counterpart. |
| `test_stitch.py` | End-to-end cases (mixed content, small/huge overlaps, list rows, floating button, 3x resolution, JPEG, reversed order, duplicates) compared against the ground truth. |
| `stress.py` | Many random sessions; counts right/wrong matched seams and unmatched seams. |

## Running

Requires Python 3 with `numpy` and `pillow` (`pip install numpy pillow`).

```sh
cd reference
python3 test_stitch.py   # prints PASS/AMBIG-OK/FAIL per case and a summary
python3 stress.py        # prints {'right': …, 'wrong': …, 'unmatched_amb': …, 'unmatched_bad': …}
```

Notes:

- Seams whose overlap is pure blank space (or has only a handful of structural rows) cannot be
  measured; they are reported as unmatched (`.estimated` in Swift). Several `test_stitch.py` cases
  contain such overlaps by chance and print `AMBIG-OK` (no content lost once blank rows are ignored)
  or `FAIL` (the static-bar fallback may drop or repeat a few rows next to an unmeasurable seam;
  this is why the app asks the user to review estimated seams). Lossless cases with structure in
  every overlap reconstruct pixel-exactly, and no lossless matched seam in `stress.py` has a wrong
  offset (lossy matches stay within a few pixels).
- Set `stitch.LOSSY = True` before `plan()` to use the cost-based matcher for JPEG/HEIC input (the
  Swift app does this per pair when either image is lossy). `stress.py` runs every configuration,
  including the JPEG ones, with the strict matcher.
