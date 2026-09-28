# DemoBench social cut — design

Swiss Pulse (Müller-Brockmann), adapted to DemoBench: grid-locked, numbers dominate, hard cuts.

## Style Prompt

A Swiss typographic poster that moves. The 1920×1080 canvas is a 12×9 grid of 160×120 cells —
the size of the DB32 screen — so every module, rule and headline snaps to a cell edge, and the
pixel footage sits in whole-number scales (1× = one cell, 3× = 3×3 cells, 6×, 9×, 12×). Paper,
black and one red. One grotesque at extreme weights, flush left, ragged right. Big numerals,
counters that run up, solid blocks sliding on the beat. Cuts land on the music's downbeats;
section changes are covered by red bands sweeping across.

## Colors

| Role | Hex | Use |
|---|---|---|
| paper | `#f2f1ec` | canvas |
| ink | `#111111` | type, solid blocks, rules |
| red | `#ff3d17` | one hit per beat: numerals, active module, wipes (DemoBench accent, pushed to Swiss red) |
| grey | `#8a8983` | secondary labels |
| line | `#d6d4cc` | grid hairlines |

## Typography

- **Archivo** (variable: weight 100–900, width 62–125). Display 900 at width 62–100, tracking −0.04em.
  Text 400–500 at width 100. Numerals 900 at width 62, `tabular-nums`.
- **Red Hat Mono** 500 — only for literal machine code and byte counts.

## Motion

- Entries `expo.out` 0.3–0.5 s; exits `power4.in` 0.2–0.3 s; blocks slide from the grid edge they touch.
- Counters run up from 0. Rules draw with `scaleX`. Nothing floats; no ambient drift.
- Beat = 0.46875 s (128 BPM). Change something on every beat in the drop.

## What NOT to Do

- No rounded corners, shadows, gradients or glows. No centered stacks.
- No off-grid placement; no smoothing or fractional scaling of footage at rest.
- No more than one red focal element per moment.
- No marketing superlatives; short, plain sentences.
