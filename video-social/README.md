# DemoBench — 45 s social cut (Swiss)

`renders/demobench-social.mp4` — 1920×1080, 60 fps, 45 s. Design: `DESIGN.md` (Swiss Pulse on a
12×9 grid of 160×120 cells, the DB32 screen size; footage always sits at whole-number scales).

| t | scene | file |
|---|---|---|
| 0 | cold open, one demo per bar: "AI agents wrote these. 4,096 bytes each. For a computer they’d never seen." | `compositions/sa-open.html` |
| 7.5 | 01 unfamiliar machine: architecture on the bus, agent's GPU code ticker | `sb-machine.html` |
| 15 | 02 every byte counts: 4,096 counter, Daybreak byte grid, 128 KiB RAM bar | `sc-limits.html` |
| 22.5 | 03 graphics and sound: what you hear / what you see (breakdown, grid build-up) | `sd-sound.html` |
| 30 | 04 no answer key: eight demos, one per beat, then the wall (drop) | `se-creative.html` |
| 37.5 | end card, red takeover | `sf-end.html` |

Music: Daybreak's soundtrack from the kick (7.5 s) to 45 s, then its outro (52.5–60 s).

## Rebuild

Footage comes from the 60 fps captures described in `../video/README.md`.

```sh
tools/prepare-media.sh <capture-dir> ../../opus_demo/artifacts/capture/audio.wav ../video/assets/footage/wall.mp4
python3 tools/inject-scope.py assets/audio/music.wav compositions/sb-machine.html 7.5
python3 tools/inject-scope.py assets/audio/music.wav compositions/sd-sound.html 22.5
npx hyperframes check
npx hyperframes render --fps 60 --quality high --video-frame-format png -o renders/render.mp4 .
# the renderer mixes about 4 dB low; put the soundtrack back at full level:
ffmpeg -i renders/render.mp4 -i assets/audio/music.wav -map 0:v -map 1:a -c:v copy -c:a aac -b:a 320k -t 45 renders/demobench-social.mp4
```
