# DemoBench — 60 s showcase video

A HyperFrames composition cut to Daybreak's own soundtrack (128 BPM, 4-bar sections of 7.5 s).
Output: `renders/demobench.mp4` (1920×1080, 60 fps).

| t | scene | file |
|---|---|---|
| 0 | title | `compositions/s00-title.html` |
| 7.5 · 11.25 · 15 · 18.75 | Pelican, Carpet, Limit Set, Daybreak (2 bars each) | `s01`–`s04` |
| 22.5 | unfamiliar machine: architecture diagram | `s05-machine.html` |
| 30 | 4 KB code / 128 KiB RAM | `s06-limits.html` |
| 37.5 | no answer key: wall of eight demos | `s07-creative.html` |
| 45 | graphics and sound from scratch | `s08-sound.html` |
| 52.5 | end card | `s09-end.html` |

Daybreak footage is always placed at the song position the music is playing (or a multiple of
16 beats away), so its beats stay in sync.

## Rebuilding the footage

The reference engine renders heavy frames over several vblanks (Pelican updates at 7.5 fps), so
the footage comes from a capture-only engine build with 32× the ticks per frame. Every frame is
then presented, as in the browser's WebGPU path; the cartridges are unchanged.

```sh
tools/build-capture-engine.sh
node .capture-engine/smooth-capture.mjs ../examples/pelican.asm --frames 1200 --out cap/pelican
# … carpet (2880), ../../opus_demo/{limit,daybreak,megamix}.asm (3600), ../examples/supersaw.asm (900)
tools/encode-footage.sh cap            # nearest-neighbour cuts at display size -> assets/footage/
python3 tools/inject-scope.py assets/audio/daybreak.wav compositions/s05-machine.html 22.5
python3 tools/inject-scope.py assets/audio/daybreak.wav compositions/s08-sound.html 45
```

Footage is pre-scaled to the exact on-screen size (12×, 3×, 2×, 6×) because the renderer smooths
scaled video.

## Render

```sh
npx hyperframes check
npx hyperframes render --fps 60 --quality high --video-frame-format png -o renders/demobench.mp4 .
```
