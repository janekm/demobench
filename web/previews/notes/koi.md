# KOI — a 4K intro for the DB32 machine

A 60-second silent demo for the DB32 demo-bench machine (profile `dynamic-1`): a koi pond
with drifting lily pads, seen from above and at a slant, through morning light, a title
pressed into the water, wind, a rain shower, koi rising to the surface and a golden
evening. Everything (the water simulation, the school, the renderer and the timeline) runs
inside the cartridge.

## Timeline (9 scenes of 400 frames; loops)

| t | scene |
|---|---|
| 0.0 s | fade in, top-down; a drop falls and its rings spread |
| 6.7 s | calm water: KOI is pressed into the surface for 1.5 s, then ripples away; the school crosses the caustic web |
| 13.3 s | the camera tilts up to ~60°: Fresnel sky reflection appears in the distance |
| 20.0 s | tilting back down |
| 26.7 s | wind: the Gerstner waves grow, caustics sharpen |
| 33.3 s | clouds and rain: the sun dims, the wave equation fills with raindrop rings, the koi go deep |
| 40.0 s | the rain stops; the koi rise to just under the surface and push ripples |
| 46.7 s | golden hour: a low warm sun, steep slant, glitter on the far water |
| 53.3 s | dusk; fade out |

## How it works

**Water surface.** The renderer never builds a mesh: each pixel intersects the mean water
plane and asks `slope(x, z)` for the surface gradient, the sum of three parts:

- **Gerstner waves** — three trochoidal waves with deep-water dispersion (ω = √(gk)). Their
  normal is the analytic Gerstner normal, `(Σ D k A cos θ) / (1 − Σ Q k A sin θ)`; the
  denominator is what sharpens crests and flattens troughs.
- **FBM ripples** — value noise with analytic derivatives, 3 octaves (2 for caustic rays),
  each octave rotated 45° and doubled in frequency, drifting with the wind.
- **GPU wave equation** — a 48×28 height field (0.25 units per cell) in RAM, stepped once per
  frame by its own GPU dispatch: `h' = h + (h − h₋₁)(1 − 1/64) + (Σneighbours − 4h)/16`, in
  16-bit fixed point, two heights packed per word, ping-ponged between two buffers.
  Raindrops (a hash per cell and frame), scripted drops and koi swimming near the surface
  displace it. For the title, the cells of a 16×7 bitmap of "KOI" are held for 1.5 s (letters
  pressed down, the rest of the rectangle flat), so the word's edges radiate ripples and it
  dissolves into rings when released. The renderer takes central differences at the four
  surrounding grid points and blends them bilinearly.

**Reflection** uses Schlick's approximation, `F = 0.02 + 0.98 (1 − cos θ)⁵`, of a sky
gradient plus the sun's glitter (the reflected ray against the sun, to the 32nd power).
Top-down, F ≈ 0.02 and the pond looks clear; at the tilted shots the far water turns into
sky.

**Refraction and Beer–Lambert.** The view ray is refracted (η = 1/1.333) and traced to the
koi's depth planes and the pond floor (1.6 ± 0.6 units deep, from noise). Light is
attenuated per channel with `exp(−σ d)` (σ = 0.45, 0.14, 0.11 per unit: red dies first),
over the view path for the ambient term and over sun path + view path for direct sunlight;
the water in between in-scatters its own colour, `scat (sun + ambient) (1 − e^{−σd})`.

**Caustics** are traced back from each receiver (floor or koi): from the receiver, the
flat-water refracted sun ray is followed up to the surface point S. There, and at S + (E, 0)
and S + (0, E), the real surface slope refracts the sunlight, and each refracted ray is
followed back down to the receiver's depth. The three landing points span a small
triangle; the caustic brightness is the ratio of its area on the surface to its area on
the receiver, `E² / |det J|` — the Jacobian of the sunlight's projection. The same
flat-water sun ray gives the koi's shadows on the floor.

**Koi.** Each pixel's refracted ray meets every koi's depth plane; the hit point is taken
into the fish's frame (along / across the body). What a vertex shader would do to a mesh
happens here to the frame: the spine is displaced sideways by a travelling wave,
`(0.015 + 0.09 u²) sin 2π(1.114 u − phase)` (u from head to tail), whose amplitude grows
toward the tail and whose phase advances with the fish's speed. Body (`0.284 √(u(0.92−u))
(1.2 − u)`), tail fin, translucent pectoral fins, eyes, round shading and noise-driven
kohaku / ogon / bekko / showa patterns follow in that bent frame.

**Lily pads** float on the mean surface as drifting notched discs, tilted with the water
for their lighting; the same test at the point where a receiver's sunlight crosses the
surface puts their shadows on the floor and on the koi.

**Boids.** The update dispatch has an extra row with one invocation per koi: cohesion,
alignment and separation over the school (all neighbours within 2.4 units, separation
inside 1), and a pull toward a point wandering around the camera's focus. Speed is clamped
to 0.35–0.9 units/s; the depth eases toward the scene's school depth. The rendering reads
the new state, so fish and ripples always agree.

**Timeline.** Ten keyframes of 13 parameters (s7.8, delta-coded with a change mask). The CPU
rebuilds the two surrounding keyframes each frame, interpolates, converts to floats and
writes them as uniforms for both GPU kernels.

## Fitting 4 KB

The first working version was 5.5 KB packed without sound. What got it under 4 KB:

- a loop over the four grid corners for the wave-equation gradient; a branch-free koi
  outline; `(1 + x/16)⁻¹⁶` for `exp`; `x / √(x² + 0.12)` as the tone curve;
- one shared sun-refraction routine for shadows and caustics, and GPU "subroutines" that
  return through a jump table on one register (there are no calls on the GPU);
- the render split into two 160×45 dispatches (each ~40% of the 1,048,576-tick budget);
- the sim dispatched over inner cells only, so the border is never written and stays zero;
- keyframes instead of per-scene start/end pairs, events packed into one word each;
- `sin` returning `sin/8`, with the ×8 folded into every caller's constants;
- rounding float literals to 1% (the range coder likes short mantissas);
- register renaming by simulated annealing against the coder's model (`tools/mregopt.mjs`).

A first release fitted music (a generative koto melody, drone, drop and rain sounds) by
cutting the lily pads, eyes, pectoral fins, koi ripples and the title; it is kept in
`src_v1_music/`. This version drops all sound and restores those features.

## Verification

- **Official validator** (`artifacts/validation/report.json`): 3,600 frames, 60 s, `ok: true`,
  WASM reference. No faults; silence (SPU disabled). The reference interpreter draws a
  new picture about every 5 vblanks (2,156 dispatches, three per picture); the sim and the
  school step once per picture.
- **Budgets:** render ≤ ~43% of the dispatch budget per half (worst pixel ~3,600 steps);
  update < 1%.
- **Browser** (kit viewer, *Assemble & run*): WebGPU, 60 fps, three dispatches per frame
  (~1–3 ms each).
