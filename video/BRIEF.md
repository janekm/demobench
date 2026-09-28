---
workflow: general-video
flow: automation
storyboard: no
message: "Small, hard, creative: 4 KB demos on an unfamiliar machine are a good test of what AI agents can really do"
aspect: 1920x1080
language: en
length: 60s
audience: people who follow LLM agents and benchmarks
---

## Intent

A motion-design video for DemoBench (demobench.janekm.com). Show recordings of the most
impressive agent-written demos in this order: Pelican, Carpet (the "magic carpet" flight),
LIMIT SET (the new hyperbolic fractal demo) and Daybreak. Use Daybreak's own music as the
soundtrack. Explain, in plain human language rather than marketing speak, why it is a good LLM
agent benchmark:

- out-of-distribution instruction set and architecture
- severe resource constraints force optimisation and efficiency
- creativity
- 3D / visual and sound design

## Assets

- `../examples/pelican.asm`, `../examples/carpet.asm`, `../../opus_demo/limit.asm`,
  `../../opus_demo/daybreak.asm`, `../../opus_demo/megamix.asm`, `../examples/supersaw.asm` —
  cartridges, recorded at 60 fps from a time-dilated build of the reference engine (every
  vblank completes its GPU work, as the WebGPU path does in the browser).
- `../../opus_demo/artifacts/capture/audio.wav` — Daybreak soundtrack (60 s, 128 BPM, 32 bars),
  used unchanged with a 2 s fade-out.

## Customizations

- Include details of the architecture with an animated diagram, and the constraints (code space / RAM).
- Keep the video within 60 s.

## Notes

- Visual identity follows the site: see `DESIGN.md`.
- Daybreak footage is always placed at the same song position as the music, so its beats stay in sync.
