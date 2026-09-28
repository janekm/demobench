# ELSEWHERE — a 4K intro for DB32

A 57.6-second vector film in the style of Éric Chahi's *Another World* (1991): flat
polygons, one 16-colour 12-bit palette per scene, black silhouettes, rain and lightning.
A red sports car drives through a rain-soaked city at night to a laboratory tower.
Lightning strikes the tower's mast, and in a white flash the film cuts to another world,
where a traveller on a cliff watches a beast walk across the face of a huge planet. It
has an original 100 BPM soundtrack. Everything runs inside the cartridge (`dynamic-1`,
packed with the kit's range coder: **4,084-byte payload**).

## Timeline (100 BPM: beat 36 frames, bar 144 frames = 2.4 s)

| t | bars | shot | music |
|---|---|---|---|
| 0 s | 0–3 | **City.** The road to the lab between flat-roofed blocks and street lamps, as in the game's intro. The skyline has lit windows and red beacons, and a band of city lights below it. The camera drifts forward while the car drives off towards the city. Lightning twice. | pad; thunder |
| 9.6 s | 4–5 | **Drive.** Side view: the car races through the rain; lamps, the lab's buildings and the skyline slide past at their own depths. | kick, rolling bass, arpeggio |
| 14.4 s | 6–7 | **Drive, close.** The wheels. | + hats, snare, lead |
| 19.2 s | 8–11 | **The lab.** The tower under billowing storm clouds; the car arrives at its foot. Lightning. | everything; thunder |
| 28.8 s | 12–13 | **The strike.** Low angle on the mast. The bolt hits it twice, then everything goes white. | thunder |
| 33.6 s | 14–17 | **Elsewhere.** Out of the white: a traveller on a cliff, stars, a planet slowly rising, and far off the beast. | a fourth up: pad, arpeggio, bass, lead |
| 43.2 s | 18–20 | The beast walks along a mesa across the face of the planet, legs swinging, eye glowing. | + kick, hats |
| 50.4 s | 21–23 | The traveller watches it go. Fade out; the film loops. | outro |

The lightning in the pictures and the thunder in the song come from the same beats.

## How it works

### Why 8-bit indexed pages

Two RGB888 pages would take 115,200 of the machine's 131,072 bytes of RAM. Two I8 pages
(160×120, one byte per pixel) take 38,400. The ~77 KB this frees holds the **span table**
(160 polygons × 120 rows × 4 bytes = 76,800 bytes), which makes the two-pass polygon
renderer below possible at all.

The palette also becomes the effects engine, as it was in Another World:

- 32 entries are computed every frame: the scene's 16 base colours (12-bit, like the
  Amiga original) and 16 lit variants for translucent light.
- Lightning multiplies every colour by 1 + 3.6·flash. Black stays black, so the city
  becomes silhouettes against a white-blue sky.
- Fades go to black or to white.

None of these touch a pixel. Each page has its own palette buffer, so a flash never tears
the picture on screen.

### Pass 1: spans (grid 160 polygons × 120 rows)

- **Animation.** Each invocation animates its polygon's instance from the shot record and
  the frame number. An instance can move at a constant velocity, or be a row of copies
  along x or z whose heights come from a hash. A row can wrap around the camera for
  endless lamps, buildings and road marks. An instance can also swing (see below), be
  scaled per axis, follow the camera, or appear only while lightning flashes (the bolt).
- **Cutting the row.** The polygon is then cut with its row. The row is a plane through the
  eye, y = v·z in view space, so each edge's crossing is found in view space before
  projection. A crossing behind the eye sends the span to the screen edge on its side.
  The road, the ground and buildings beside the camera therefore need no clipping code;
  near-plane culling applies only to ellipses.
- **Span format.** The span is stored as one word, `((xr − 1 + 0x4000) << 16) | (0x4000 − xl)`,
  with xl unclipped.
- **Swing.** Rotation is 2·atan(u) with u = amplitude × triangle(ω·t), using
  cos = (1 − u²)/(1 + u²) and sin = 2u/(1 + u²). There is no sine: it swings the beast's
  legs, and at high rates it passes for the car's spinning wheels.
- **Shapes.** Shapes are lists of convex (y-monotone) polygons with signed-byte (x, y, z)
  vertices, or ellipses. Solids have no culling; they list their faces in painter's order
  and are mirrored for the other side of the road.

### Pass 2: resolve (grid 160 × 120, one invocation per pixel)

- **The span walk.** Each pixel walks its row's spans from the front. One add of the
  pixel's constant x − (x << 16) and one mask with 0x40004000 tests both ends at once:
  each 16-bit half has "inside" in bit 14. That is 7 ticks per polygon. The first opaque
  polygon wins (painter's order, walked front to back). Entry 0 is the background and
  covers every pixel, so the loop needs no counter.
- **Translucency.** Translucent polygons (headlight beams, lamp halos, the planet's
  glow) move the pixel to the lit half of the palette, and the walk continues.
- **Materials.**
  - Lit windows are hashed on (x − the span's left edge, y), so they scroll with their
    building.
  - The sky is banded near the horizon, with stars.
  - The ground has a band of twinkling city lights below the horizon.
  - Rain falls 4 pixels a frame along a 1:2 slant and lights whatever is under it.

### CPU

- **Per shot.** At a shot change the CPU builds the draw list: every polygon of every
  instance, in list order. Each entry is [polygon, record | copy]. It also copies the
  7-word shot record into uniforms.
- **Per frame.** It finds the latest lightning strike in the shot's beat mask and computes
  a flicker. It then runs the two passes. Both passes share their bindings; only the
  span table's read/write flag changes between them, so the WebGPU preview keeps two
  cached pipelines. Finally it flips page and palette at vblank.

### Sound

- **The engine.** It is the MEGAMIX / LIMIT SET FM engine: stateless, one invocation per
  stereo sample, echoes and reflections as extra taps, chord-relative notes. It is retimed
  to 100 BPM (7,200-sample sixteenths, 24 bars).
- **Changes for ELSEWHERE:**
  - sidechain ducking removed;
  - a quadratic exp2 (±3 cents);
  - the soft limiter uses one gain from the mid level.
- **The song.** Am | F | Dm | E, lifting a fourth for the alien world. A haunting lead, an
  8th-note bass, a 16th arpeggio, pad, drums, and a thunder voice: pitch-swept noise with
  dotted-eighth echoes.

### Size

The RAM image is 6,852 bytes; the range coder packs it to 3,732, plus the 352-byte decoder.

| part | packed bytes |
|---|---:|
| span kernel (animation, projection, palette) | 1,021 |
| shots, palettes, instance lists | 622 |
| SPU synthesiser | 536 |
| shapes | 458 |
| CPU | 354 |
| song | 325 |
| resolve kernel | 313 |
| MMIO scripts | 103 |

What made it fit:

- Both passes share their bindings (one flags word switches).
- The palette work is split: the CPU finds the lightning (integer), and GPU lanes build
  the 32 colours (float).
- Rotation is rational instead of a sine.
- The record length lives in the low bits of the shape offset.
- The horizon row doubles as the projection centre, and the focal length is fixed.
- The instance lists are reused by several camera setups (7 shots, 4 lists).
- Float literals are rounded by the preprocessor. Those that matter are marked exact
  (16384.5 in the span encoding, for example).
- Register renaming for the coder's byte lanes (`tools/mregopt.mjs`).

## Verification

- **Official validator** (`../artifacts/elsewhere/validation/report.json`): 3,600 frames
  (60 s) on the WASM reference, `ok: true`. No faults, no audio overruns, no clipped
  samples; audio peak 0.95, SPU at most 27,948 ticks per block (43% of the budget).
- **Browser viewer:** GPU and SPU both on WebGPU. Host at 60 fps with a new frame every
  vblank (two dispatches per frame, ≈0.5 ms each; SPU block ≈1.3 ms). It played past a
  whole loop (frame 4,930) with no fallback and no underruns or overruns.
- **WASM reference:** heaviest dispatch 384k ticks (37% of the budget); a new frame every
  1–3 vblanks.
- **WebGPU step limit (8,192 per invocation):**
  - GPU: worst 984 instructions (`tools/msim.mjs`, every shot).
  - SPU: worst 6,175 per sample (`tools/mspu.mjs`, every bar).
