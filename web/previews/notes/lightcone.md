# LIGHTCONE — a 4K intro for the DB32 machine

A 57.6-second audiovisual demo for the DB32 demo-bench machine (profile `dynamic-1`).
Light is slowed down so you can watch it do things demos don't usually show: light
echoes sweeping through a dust nebula, a flight to 0.99 c with aberration and Doppler
shift, a title that is rotated by light-travel time (Terrell rotation), and photoelastic
force chains in glass disks. The soundtrack is original hard techno at 150 BPM. Everything
(rendering, synthesis, sequencing, text) runs inside the cartridge.

## Timeline (9 scenes of 4 bars = 384 frames each; loops)

| t | scene | music |
|---|---|---|
| 0.0 s | **Light echo.** A star in a dust nebula flares on every bar; each flare's echo reveals a slice of the dust | pad swell, a boom and crash on every bar, riser |
| 6.4 s | the kick: a warm echo on beats 1 and 3, drifting round the star | kick, rolling bass, open hats |
| 12.8 s | claps add blue echoes on 2 and 4, closer into the dust | + claps, 16th hats, acid line |
| 19.2 s | **Relativistic flight** down a tunnel of glowing rings, from rest to 0.95 c | acid opens up; snare roll and riser |
| 25.6 s | **Terrell rotation:** LIGHTCONE flies past at 0.8 → 0.3 c | drop: boom, chord stabs |
| 32.0 s | **Photoelastic disks**, the load slowly rising | breakdown: pad, acid; roll and riser |
| 38.4 s | every kick surges through the force chains | second drop |
| 44.8 s | 0.96 → 0.99 c | full groove |
| 51.2 s | back at the star: the last echoes fade | kick for two bars, then pad and boom |

## The effects

**Light echo** (`render.s`, ECHO). Light from a flare at time t0 reaches the camera
after scattering off dust at X if `s + |X − L| = c (t − t0)`, where s is the distance
along the camera ray. That surface is an ellipsoid with the star and the camera at its
foci, so each echo is a thin shell per ray with a closed-form distance:
`s = (R² − |C|²) / (2 (R + D·C))`, R = c (t − t0). There is no marching. For each of the
last eight beats the kernel evaluates two octaves of ridged 3D value noise (the dust
sheets) at that point. The brightness includes the shell's Jacobian (per unit length of
the ray), a forward-scattering phase function and the pulse tail. Young echoes are
white, old ones red (kicks) or blue (claps). As in real light echoes (V838 Monocerotis),
the rings appear to expand faster than light.

**Relativistic flight** (SPACE). Each camera-frame ray is aberrated into the lab frame:
`d = (dx D, dy D, (dz − β)/q)`, with `q = 1 − β dz` and Doppler factor `D = 1/(γ q)`. The
tunnel is 3-unit rings every 2 units, found by stepping through ring planes along the
ray. Every ring is a blackbody at 3,500 K, so a ring seen through factor D is exactly
`Planck(D·T)`: per channel `W / (2^(A/D) − 1)`. That one formula gives the colour shift
and the headlight brightening. At 0.99 c the whole tunnel, including the part behind
the camera, crowds into a blue-white disc ahead.

**Terrell rotation.** The letters are 29 boxes (a 2×4 stroke font). In the text's rest
frame a camera ray is still straight: light arriving now left the text at t − s/c, so the
ray direction becomes `((d.z + β) γ, d.y, d.x)`, contraction included, with the lab length
s along it. Slab tests against the boxes then show the text as it is seen: stretched and
blue-shifted while approaching, contracted, rotated (you see the letters' sides) and
red-shifted while receding.

**Photoelasticity** (STRESS). Disks in a hexagonal packing between crossed circular
polarisers. Each disk sums six Flamant point loads at its contacts,
`σ += k q qᵀ` with `k = −F (q·u)/|q|⁴`. Contact forces are heavy-tailed (hashed on the
contact point, so both disks agree), grow with depth and surge on each kick. The
fringe order is `N = C (σ1 − σ2)`, and the colour is the sum over six wavelengths of
`sin²(π N · 550/λ)`, which gives the Michel-Lévy interference colours.

**Post.** A filmic (ACES-fit) curve, gamma, grain, a 2×2 sub-pixel jitter over four
frames, and a temporal blend with the frame on screen (anti-aliasing plus motion trails).

## Soundtrack

Hard techno at 150 BPM in F minor: 4,800 samples per 16th, 36 bars. It is fully
stateless (one SPU invocation per sample, at most ~1,250 steps). A table of 14 voice entries
shares one engine: trigger masks, a decay envelope, drive into a soft clipper, a kick
sidechain, pan. There are four oscillator types:

- pitch-swept sine (kick 360 → 45 Hz, boom, a rolling bass on the 16ths after each kick)
- noise (hats, clap, crash, snare roll, riser)
- a five-note chord in detuned pairs (saw stabs, triangle pad)
- a CZ-style resonant saw for the acid line: `(1 − p) sin(2π r p)`, with r swept by a
  per-note envelope and the bar's cutoff automation

Delay "echoes" are extra voice entries with shifted trigger masks. Per-bar words hold the
voice flags, pad level and acid cutoff, lerped across each bar. A soft limiter
`x/√(1+x²)` sits on the output.

## Fitting 4 KB

The 6,672-byte RAM image (code, tables, song, font) packs to 3,719 bytes with the kit's
range coder (+352-byte decoder), unpacking to 0x2CE00. What made it fit:

- **CPU-side parameters.** Scene records are delta-coded (a change mask plus the
  changed words). The CPU lerps each [start | end] s7.8 pair by scene progress, converts
  it to float bits, and writes it to a GPU uniform, so each parameter use in a kernel is
  a single `g.uniform`.
- **One GPU kernel, one 160×90 dispatch per frame.** The two pixel passes of the title
  scene reuse the same camera code, by jumping back to it.
- **Table-driven synth.** One engine; the voices are 16-byte records. The flag bit sits in
  the header's low 5 bits, so `shr FL, header` tests it directly (shift counts use the
  low 5 bits).
- **Compression-friendly code.** Register renaming by simulated annealing against the
  coder's model (`tools/mregopt.mjs`, ≈ 80 bytes), rounded float literals, byte tables.
- **Letterbox.** The two RGB888 pages share their 15 black rows, which frees 7.2 KB of
  RAM.

## Verification

- **Official validator** (`artifacts/validation/report.json`): 3,600 frames, 60 s,
  `ok: true`, WASM reference. No faults, no audio overruns, no clipping; peak 0.91.
- **Budgets:**
  - GPU: worst 2,358 steps per pixel (WebGPU limit 8,192); worst dispatch ~568k ticks,
    54% of the 1,048,576 budget.
  - SPU: ≤ 11% of the per-block work budget.
  - The WASM reference draws a new frame every 1–3 vblanks (2,573 frames in 3,600 vblanks).
- **Browser** (kit viewer, *Assemble & run*): GPU and SPU both on WebGPU. 59.4–60.7 host
  fps through every scene and across the loop seam, 0 playback underruns.
- **Audio** was balanced by measurement, not by ear: per-voice section RMS, waveforms and
  spectrograms (`tools/audio.py`, `tools/wplot.py`, `tools/solo.sh`).
