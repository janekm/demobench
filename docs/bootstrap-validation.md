# Bootstrap acceptance — 2026-09-25

The `bootstrap-1` CPU/video system is implemented and was exercised in native Rust tests, headless WebAssembly, Chromium, and WebKit. GPU, synthesizer, DMA, general IRQ/timer devices, snapshots, and benchmark grading are outside this milestone.

## Build and component checks

- Rust 1.92.0, wasm32-unknown-unknown; Node 24.16.0 on macOS arm64.
- `npm test`: **31 Rust tests and eight WASM integration tests passed**.
- `cargo fmt --all --check` and browser JavaScript syntax checks passed.
- `machine.wasm`: **103,674 bytes**, no imports, maximum linear memory 16 MiB.
- Final module SHA-256: `ec6d76802a55e957be0019fe83e640d2d761d6cf4d173b2cd69ebde118a76887`.

Coverage includes CPU arithmetic/control flow, malformed encodings, checked memory, cartridge boundaries, all five pixel formats, per-line palette reads, configuration latching, instruction commits at exact ticks, vblank waiting, run-slice equivalence, bounded host calls, and malformed assembler expressions that return errors without trapping the module.

## Headless image captures

Both cartridges were assembled inside the WASM module and run for 120 frames / 24,576,000 virtual ticks. Their raw RGBA outputs repeat exactly across fresh runs.

| Demo | Payload | Format | Distinct colours | CPU state after capture |
| --- | ---: | --- | ---: | --- |
| Aurora | 864 B | I8 | 210 | Waiting for vblank |
| RGB study | 436 B | RGB888 | 13,812 | Halted; video continues |

Raw RGBA SHA-256:

- Aurora: `c03c9fd4b0f01ba5bff67c246705658a108c586fa00a0e2b3a5c406cb201a07c`
- RGB study: `867960e78286296abfc5f703483dd0ca5099d99f5aff24e80c934abffe354f10`

Captures, submitted cartridge bytes, and machine/module identities are in `artifacts/aurora.{png,db32,json}` and `artifacts/rgb-study.{png,db32,json}`. Recreate them with the capture commands in the README; generated artifacts are ignored by source control.

## Browser acceptance

Chromium and WebKit both loaded the final module hash above. For each demo, the actual canvas RGBA hash matched a fresh headless run at the same virtual frame/tick. Both browser runs passed:

- Playback pause and exact one-frame stepping.
- Demo selection and in-WASM assembly.
- Assembly error display and reset to the last valid cartridge.
- Source edit/rebuild and resumed output.
- PNG and cartridge downloads.
- 390-pixel mobile layout without horizontal overflow.
- No uncaught page errors.

The actual rendered images, desktop viewer, and mobile layout were visually inspected. Detailed browser records and screenshots live in `artifacts/browser-{chromium,webkit}.json` and the corresponding viewer/mobile PNGs.

The headless host is Node's WebAssembly engine. Wasmtime integration and the full-machine benchmark acceptance gates remain future work; they are not implied by these bootstrap results.

## Ray-tracing example — reflections and point lighting

`examples/ray-tracer.asm` traces three surface hits per pixel, including sphere-to-sphere and floor reflections, entirely in guest CPU instructions. Each hit tests a finite shadow ray to a point light, with diffuse/specular lighting and distance attenuation. A constant ambient term remains; indirect diffuse illumination is not simulated. Its payload is **2,072 bytes** (2,104 bytes including the cartridge header). It renders progressively in RGB888 and halts after writing the last pixel.

After this extension, `npm test` passed all **31 Rust and ten WASM integration tests**, including repeated fresh runs of this cartridge. Geometry fixtures verify nearest intersections and exclusion of objects at/beyond the light distance. Pixel tests verify that changing a reflected sphere's material changes its image on another sphere, and that a sphere shadow suppresses direct illumination while unoccluded lighting stays unchanged. At 480 frames the CPU is halted, with 5,708 distinct colours. The completed 160 × 120 canvas in the Codex in-app browser matched the headless raw RGBA SHA-256 exactly:

`e8d1dde2d65785baf1e41ca0fa2eaee571e740fff31fc4fdeaec56051fbf0049`

The completed scene was visually inspected in the browser. Captures are in `artifacts/ray-tracer.{png,db32,json}`. The earlier Chromium/WebKit control and layout checks above cover the original two examples; this addition received the in-app browser image comparison and headless regression checks described here.
