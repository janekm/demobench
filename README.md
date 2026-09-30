# demo-bench

A benchmark project for agents that learn a small unfamiliar machine, write a tiny executable demo, inspect its output, and improve it within a fixed development budget.

[Live demos](https://demobench.janekm.com) · [Engine repository](https://github.com/janekm/demobench) · [Standalone authoring skill and local engine](https://github.com/janekm/demobench-agent-kit)

**Implemented: `bootstrap-1` CPU/video, `gpu-1` CPU/GPU/video, `spu-1` CPU/GPU/SPU/video, and `dynamic-1` RAM-kernel profiles in WebAssembly.** Cartridge versions 1–3 retain their existing behavior; `.profile spu-1` selects version 3 and enables programmable audio. DMA, general IRQ/timers, the Wasmtime host, and the scored benchmark remain planned.

All four profiles share a 4,096-byte cartridge limit, 128 KiB working RAM, a sixteen-register integer CPU, and 160×120 scanout. Video supports 1/2/4/8-bit indexed buffers with RGB palettes and RGB888. Guest CPU or GPU assembly writes every displayed pixel or palette entry. In `spu-1`, guest `g.*` kernels also write stereo sample buffers and persistent DSP state in RAM. The reference CPU, GPU, SPU, assembler, bus, clock, and video controller execute in the same import-free WASM module. The browser can accelerate eligible guest GPU and SPU kernels using WebGPU.

The homepage explains the benchmark around an animated diagram of the machine, features the strongest agent-made demos, points to the agent kit, and ends with the full cartridge shelf. The machine boots in the background after the page loads, so clicking any demo runs it live, with sound, straight away. The page's tiling background is itself a cartridge, [backdrop.asm](examples/backdrop.asm) (2,744 bytes): a checkerboard of tumbling cubes on a travelling wave, ray traced per pixel by two GPU jobs a frame, with sun shadows. An orthographic camera over a world that repeats every four cells makes the 160×120 frame tile seamlessly. It runs on a second machine instance in a worker, using WebGPU; without WebGPU the page shows one still frame. The Studio (`/studio.html`) offers playback, pause, frame stepping, reset, editable assembly, a live register and telemetry inspector, a listing, and PNG/cartridge export. A Node headless host executes the identical module and captures PNG plus exact raw-frame hashes. The future Wasmtime embedding is not implemented yet.

## Run locally

Requires Rust/Cargo with `wasm32-unknown-unknown` and Node.js 22 or newer. There are no third-party Rust crates or npm runtime dependencies.

```sh
git clone https://github.com/janekm/demobench.git
cd demobench
rustup target add wasm32-unknown-unknown
npm run dev
```

Open **http://127.0.0.1:4173** for the cartridge shelf, or **/studio.html** for the editor and inspector. `npm run dev` builds the WASM module and copies the examples before starting a localhost-only server. Use `PORT=4174 npm run dev` to change the port.

```sh
npm test
npm run capture -- --demo aurora --frames 120
npm run capture -- --demo rgb-study --frames 120
npm run capture -- --demo ray-tracer --frames 480
npm run capture -- --demo gpu-ray-tracer --frames 8
npm run capture:audio -- --frames 480
npm run capture:audio -- --demo neon-stadium --frames 1800
npm run bench:gpu -- --pixel-shift 0
npm run bench:gpu -- --pixel-shift 1
```

`npm test` rebuilds the exact WASM artifact and runs Rust and WASM integration tests. Video capture writes a PNG, a `.db32` cartridge, and a JSON record to `artifacts/`. `capture:audio` runs the reference WASM path and writes a WAV, PNG, cartridge, and JSON report with PCM and WAV hashes. `npm run build` builds without starting the server.

## Self-extracting cartridges and dynamic kernels

`npm run pack -- source.asm -o packed.db32` compresses CPU code and data into a
self-extracting cartridge. Use `.profile dynamic-1` to compress GPU/SPU kernels
as well, or generate and rewrite kernels in guest RAM. Version 4 snapshots
validated code on each dispatch/audio block; the older profiles retain their
original behavior. The decoder and compressed bytes still share the 4,096-byte
payload limit. Sources larger than 4 KiB are supported by the offline linker.

See the [packer guide](docs/packing.md), [dynamic kernel contract](spec/dynamic-1.md),
and [runtime kernel-editing example](examples/dynamic-kernel.asm). The packer
compares LZ, instruction-byte shuffling, adaptive range coding and a stored
fallback, and verifies extraction in WASM. `npm run bench:pack` measures actual
demos and checks their rendered frames and audio against delayed originals.

## Included demos

| Demo | Payload | Behavior |
| --- | ---: | --- |
| [ASTRA](examples/astra.asm) | 4,016 B | Eight-chapter, 60-second audiovisual intro with recursive crystals, hyperspace tunnels, Julia fractals and a 128 BPM stereo synth score |
| [Pelican](examples/pelican.asm) | 4,088 B | Packed `dynamic-1` cartridge: a ray-traced pelican riding a bicycle along a seaside promenade past a harbour town and sailboats, with a 100 BPM calypso soundtrack (steelpan, bass, shaker, surf) |
| [Supersaw](examples/supersaw.asm) | 4,012 B | JP-8000-style supersaw (21 PolyBLEP saws in three layers) playing a riff in the style of Darude's *Sandstorm* at 136 BPM, with FDN reverb, ping-pong delay, bass and drums; the GPU draws a Goertzel LED spectrum analyser from the live mix |
| [Carpet](examples/carpet.asm) | 4,093 B | Packed `dynamic-1` cartridge: a 48-second ray-marched flying-carpet flight over a procedural archipelago (castle, mana orbs, erupting volcano, balloon and fireball) with a D-hijaz soundtrack |
| [LIMIT SET](examples/limit-set.asm) | 4,074 B | Packed `dynamic-1` cartridge: a 60-second flight through hyperbolic space, ray traced per pixel, that sweeps one honeycomb parameter from a flat cubic lattice through {4,3,5}, {5,3,4} and {4,3,6} into the fractal limit set, with a 128 BPM soundtrack in D minor |
| [Elsewhere](examples/elsewhere.asm) | 4,084 B | Packed `dynamic-1` cartridge: a 57.6-second vector film in the style of *Another World* (a car in the rain, lightning on a lab tower, a beast on an alien world), drawn by a two-pass GPU span renderer into 8-bit indexed pages, with a 100 BPM soundtrack |
| [Lightcone](examples/lightcone.asm) | 4,071 B | Packed `dynamic-1` cartridge: 57.6 seconds of slowed-down light (light echoes in a dust nebula, a flight to 0.99 c, Terrell rotation, photoelastic force chains) with 150 BPM hard techno |
| [Koi](design/previews/src/koi.asm) | 4,061 B | Packed `dynamic-1` cartridge by Opus 5.5: a silent 60-second koi pond (GPU wave equation, Gerstner waves, refraction, caustics and a boid school) through wind, rain and a golden evening |
| [Pelican Pedal Club](design/previews/src/pelican-pedal-club.asm) | 4,045 B | Packed `dynamic-1` cartridge by Sol 6.1: a pelican pedalling along the beach past a palm and parasol, fifty ray-traced ellipsoids, sun-glitter ocean and a 120 BPM loop |
| [Pelican on a Bicycle](design/previews/src/pelican-bicycle.asm) | 4,094 B | Packed `dynamic-1` cartridge by Sonnet 5.5: a pelican in sunglasses circling on the sand at golden hour, ray-traced capsules and shadows, and an 88 BPM FM score |
| [Aurora](examples/aurora.asm) | 864 B | I8 night landscape with animated palette, synchronized using WFI |
| [RGB study](examples/rgb-study.asm) | 436 B | CPU-generated true-colour grid and luminous diamond; CPU halts after drawing |
| [Ray tracer](examples/ray-tracer.asm) | 2,072 B | Sphere-to-sphere and floor reflections, point-light shadows, and a checkerboard; integer CPU ray tracing |
| [GPU ray tracer](examples/gpu-ray-tracer.asm) | 1,652 B | Animated point lighting, shadows, three surface hits, sphere/floor reflections, and double-buffered presentation |
| [Signal garden](examples/signal-garden.asm) | 1,400 B | Guest-programmed stereo signal generation and visual output using the shared kernel ISA |
| [Neon stadium](examples/neon-stadium.asm) | 3,604 B | Sustained seven-saw stereo riff, drums, bass and an eight-bar build/drop at 128 BPM |
| [Backdrop](examples/backdrop.asm) | 2,744 B | The homepage's tiling wallpaper: tumbling cubes ray traced on the GPU, with an orthographic camera chosen so the frame tiles seamlessly |

The sizes exclude only the fixed 32-byte validated cartridge header. No host-generated images, fonts, or asset sidecars are loaded into the guest.

ASTRA is the unchanged submitted `astra.asm` from the sibling `../astrademo` project. Open `/studio.html?demo=astra` to run it, then enable **Sound on** for its soundtrack. The shelf includes an animated preview and keyframes from all eight chapters, captured with the reference WASM engine. Its 4,016-byte payload leaves 80 bytes free; heavy reference GPU dispatches span multiple video frames, while WebGPU provides accelerated playback. To validate it and regenerate its shelf assets (preview capture requires FFmpeg):

```sh
npm run build
npm run validate:demo -- examples/astra.asm --frames 3600 --out artifacts/astra-validation
node design/tools/make-previews.mjs --only astra
node design/tools/publish-web.mjs
```

Pelican is the unchanged submitted cartridge from Opus 5.5 (`../opus_demo/pelican.asm`, readable sources in `../opus_demo/pelican/`); it replaces the earlier silent `gpu-1` version and assembles byte-identically to the submitted `.db32`. It is a packed `dynamic-1` cartridge: each frame a prepass writes the animated primitive table and three render strips ray-trace the image, while the SPU plays an 8-bar calypso loop. Its 4,088-byte payload leaves 8 bytes free. The reference WASM GPU presents a new image roughly every eighth video frame; WebGPU plays it at full rate. Its shelf preview covers one 20-second camera swing (`node design/tools/make-previews.mjs --only pelican`).

Supersaw and Carpet are the unchanged submitted cartridges from the sibling `../opus_demo` project (`supersaw.asm`, `carpet.asm`); both assemble byte-identically to their submitted `.db32` files on the current engine. Carpet is the packer's output: its readable sources, route and packing report live in `../opus_demo/carpet/` and `../opus_demo/artifacts/carpet/`. The reference WASM engine renders Carpet roughly every third or fourth vblank; WebGPU plays both at full rate. Regenerate their shelf assets with `node design/tools/make-previews.mjs --only supersaw,carpet`.

LIMIT SET and Elsewhere are the unchanged submitted cartridges from `../opus_demo` (`limit.asm`, `elsewhere.asm`; readable sources in `limit/` and `elsewhere/`). Lightcone is the unchanged `lightcone.packed.asm` from the sibling `../opusdemo2` project. All three are packed `dynamic-1` cartridges and assemble byte-identically to their submitted `.db32` files on the current engine. The reference WASM engine presents a new image every one to three vblanks; WebGPU plays them at full rate. Each author's README, minus its local file table and build steps, is published as a notes page (`/notes.html?demo=elsewhere`), linked as **How it works** from the cartridge's details. Regenerate their shelf assets and notes with `node design/tools/make-previews.mjs --only limit-set,elsewhere,lightcone`.

Koi (`../opusdemo2/koi/koi.packed.asm`), Pelican Pedal Club (`../sol61demo/artifacts/pelican.packed.asm`) and Pelican on a Bicycle (`../sonnet_demo_2/deliverable/pelican_bicycle.packed.asm`) are unchanged submitted cartridges that assemble byte-identically to their `.db32` files. Regenerate their shelf assets with `node design/tools/make-previews.mjs --only koi,pelican-pedal-club,pelican-bicycle`.

Edit the homepage, Studio and notes page in `design/console.html`, `design/studio.html` and `design/notes.html`, then run `publish-web.mjs` to refresh the deployed pages and preview records in `web/`.

The ray tracer progressively fills the screen, then halts. It traces up to three surface hits per pixel (two reflection bounces), including sphere-to-sphere, sphere-to-floor, and floor-to-sphere paths. Each hit casts a finite shadow ray toward a point light; unblocked surfaces receive diffuse/specular illumination with distance attenuation. Positions use Q4 fixed point, directions use Q10, and normalization, square root, division, and gamma correction all run as guest instructions. A small constant ambient term remains in shadows; this is bounded Whitted ray tracing, without indirect diffuse illumination. The example finishes within 480 virtual frames (eight seconds at 60 Hz). Select **Ray tracer / spheres & reflections** in the viewer's demo menu.

## Programmable GPU

The 64-lane GPU executes counted guest kernels with 32 registers per lane, integer and binary32 scalar/vector math, ray–sphere intersection, lane-dependent branches, checked buffers and a finite instruction budget. It has no scene renderer: the example's kernel implements traversal, normals, lighting, shadows, reflection bounces and pixel output. Two RGB888 pages use 115,200 bytes of the 128 KiB RAM. GPU completion and vblank wake the CPU without a polling loop.

Select **GPU ray tracer / real-time reflections** in the viewer. Its quality selector switches between the default **160×120 rays** and **80×60 rays expanded into 2×2 pixels**; the display remains 160×120. The selector edits the visible `PIXEL_SHIFT` source constant and reassembles that cartridge. Virtual frame-budget usage appears separately from host performance. `bench:gpu` measures the reference WASM engine after warmup and writes a host/module-specific report; [GPU validation](docs/gpu-validation.md) records measured performance and browser parity.

The renderer selector defaults to **Auto · WebGPU preferred**. Actual cartridge instructions compile into compute shaders with native GPU math; edited kernels use the same path. Full-detail rendering reaches about 60 browser FPS on the validated M3 Max. **WASM · reference** remains available, and unsupported kernels or unavailable hardware fall back automatically. Accelerated mode favors speed over numerical and timing equivalence, and displays host timings instead of a virtual GPU budget. See [WebGPU validation](docs/webgpu-validation.md).

The [GPU contract](spec/gpu-1.md) defines reference instruction encodings, MMIO, timing, numerical behavior and faults. The [architecture](docs/gpu-kernels.md) describes the implemented WebGPU compiler and its buffer restrictions. The ISA is independent of WGSL and WebGPU resource APIs.

WebGPU has no separate 8,192-instruction authoring limit. Its per-thread termination guards cover the reference work budgets: 1,048,576 instructions for GPU jobs and 65,536 for SPU jobs. These conservative guards preserve bounded execution without rejecting longer reference-valid paths. The canonical limits remain whole-job virtual ticks; accelerated float behavior and device/host failures can still differ.

## Programmable audio

The [spu-1 contract](spec/spu-1.md) adds an audio-clocked compute job without fixed oscillator, voice, envelope, filter, instrument, or mixer registers. At each 65,536-tick block boundary, the SPU executes guest `g.*` instructions over checked bindings and uniforms. The kernel writes 256 interleaved stereo binary32 frames (2,048 bytes) to RAM at 48 kHz. DSP state persists in ordinary guest RAM, so a kernel can implement recurrence, synthesis, sample playback, effects, and mixing itself. Reference work is limited to 65,536 virtual compute ticks per block.

The viewer starts muted; **Sound on** is an explicit user action that enables AudioWorklet playback of queued PCM. Eligible SPU jobs can use WebGPU for fast preview, including atomic reads from their writable state buffers. Cross-invocation read/write dependencies have no canonical hardware order, so use the WASM reference for exact results and `capture:audio` for reproducible WAV evidence. See [SPU validation](docs/spu-validation.md) and the [shared kernel architecture](docs/gpu-kernels.md).

Select **Neon stadium / supersaw & drums** for an homage to Zombie Nation's *Kernkraft 400* with an original riff, seven stereo saws spread across ±4.5% detune, an E3-centred lead, bass, kick, snare and offbeat hats. The lead holds quarter, half and dotted-quarter notes with continuous phase across ties, a 5 ms attack and a 30 ms release. Its eight-bar phrase loops at 128 BPM, building into a full drop at 7.5 seconds. The saw discontinuities, envelopes, noise generation, drum sequencing and mix all run as guest instructions. [Demo notes and capture evidence](docs/neon-stadium.md) describe the program. **Signal garden** remains the simpler technical study with sustained tones and an arpeggio.

## Deploy

The public viewer is configured for **https://demobench.janekm.com** using [Cloudflare Workers Static Assets](https://developers.cloudflare.com/workers/static-assets/) and a [Custom Domain](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/).

```sh
npm ci
npm run deploy:check
npm run deploy
```

Both deployment commands rebuild the WASM engine and public examples first. `deploy:check` performs a Wrangler dry run; `deploy` uploads the `web/` assets and attaches the custom domain using the authenticated Cloudflare account. The viewer's WebAssembly, worker, WebGPU and audio code all execute in the browser. Cloudflare serves static files. The asset rules exclude the browser QA script and require cache revalidation for these unversioned files.

After deployment, verify the live viewer and compare `/machine.wasm` with the SHA-256 in the local `web/build.json`. A successful upload alone does not verify browser execution. The agent kit remains a separate distribution in `../demobench-agent-kit`.

## Agent authoring skill

[The standalone agent kit](https://github.com/janekm/demobench-agent-kit) is a separate repository; clone it beside this project as `demobench-agent-kit` for the maintenance commands below. It contains a short authoring skill, one 22-line RGB starter, a pinned import-free WASM engine, CPU/GPU/SPU contracts, a headless validator and the browser viewer. Agents need only Node.js 22+, with no Rust toolchain or dependency on this engine-development checkout.

From this project, `npm run skill:pack` rebuilds the engine and refreshes the sibling kit's runtime and contract extracts. Use `npm run skill:pack -- --kit /absolute/path/to/kit` for another location. The kit owns its authoring instructions, manifest, checks and archive generation; its `npm run bundle` produces `artifacts/demo-bench-skill.tar.gz` independently of this checkout. Commit its bundled WASM so agents can use a fresh clone immediately.

```sh
node ../demobench-agent-kit/scripts/validate.mjs ./my-demo.asm --frames 120 --out ./artifacts/my-demo
PORT=4174 node ../demobench-agent-kit/scripts/viewer.mjs
```

The validator accepts source or a `.db32` cartridge, drains audio every frame, and writes sampled PNGs, the cartridge, `report.json`, and a 48 kHz stereo WAV for SPU programs. It exits nonzero for assembly/load/runtime failures and reports the tested interval and exact engine hash. Only artifacts listed in the latest report belong to that run. Validation does not judge composition or establish real-time performance; inspect the images and audition the audio. The packaged viewer includes only the tiny starter; paste new source into its editor to preview it with WASM or optional WebGPU acceleration.

## Subsystems

| Path | Responsibility |
| --- | --- |
| `crates/db-contracts` | Memory map, timing, opcodes, bus and fault types |
| `crates/db-core` | CPU instruction semantics and instruction costs |
| `crates/db-gpu` | Kernel interpreter, vector/intersection math, checked bindings, leases and dispatch timing |
| `crates/db-spu` | Audio block scheduling, shared-kernel dispatch, PCM validation and bounded queue |
| `crates/db-video` | Register interface, queued configuration, palettes and scanline capture |
| `crates/db-asm` | CPU/kernel assembler, versioned cartridges, diagnostics and listing |
| `crates/db-wasm` | Composition, checked bus, exact scheduler and WASM host ABI |
| `web/` | Cartridge shelf (`index.html`), Studio viewer (`studio.html`), cartridge notes (`notes.html`), browser worker, WebGPU kernel compiler/backend, screen, controls and source editor; `classic.html` is the single-page viewer packaged into the agent kit |
| `design/` | Design explorations, preview capture (`tools/make-previews.mjs`) and publishing of the shelf and Studio into `web/` (`tools/publish-web.mjs`) |
| `web/audio-player.js`, `web/audio-worklet.js` | Muted-by-default PCM queue, resampling and playback transport; no guest synthesis |
| `scripts/` | Build, local server, headless host, video/audio capture and integration tests |

[The bootstrap contract](docs/bootstrap-contract.md), [gpu-1 contract](spec/gpu-1.md), and [spu-1 contract](spec/spu-1.md) are the implemented sources of truth. At equal ticks, CPU commit precedes GPU commit, SPU block execution, and video scanout. RAM is distinct from the module's capped 16 MiB host memory. Video, GPU, and SPU continue after CPU HALT. WFI wakes on vblank and, in gpu-1/spu-1, GPU completion; SPU blocks do not wake it.

DMA, general interrupt handlers, timer devices, snapshots, and benchmark grading are deferred. Access to absent device pages faults; bootstrap-1 still rejects GPU accesses and profiles 1/2 reject SPU accesses.

## Browser verification

`scripts/test-browser.mjs` drives `/studio.html` and tests real UI controls, exports, mobile layout, and exact canvas/headless raw-frame parity. It requires Playwright and its browsers as an optional QA dependency, plus a running local server:

```sh
npm run test:browser
npm run test:browser -- --webkit
```

If Playwright is supplied externally, set `DEMO_BENCH_PLAYWRIGHT_MODULE` to its module entry. `DEMO_BENCH_BROWSER_EXECUTABLE` optionally selects an installed browser executable. Browser reports and screenshots are written to `artifacts/`. Chromium and WebKit were both exercised during bootstrap acceptance.

## Design documents

- [Machine architecture](docs/architecture.md): CPU, memory, timing, peripherals, component boundaries, and deliberate exclusions.
- [Programmable micro-GPU](docs/gpu-kernels.md): kernel execution, lanes, buffer bindings, scheduling, and resource limits.
- [Programmable SPU](spec/spu-1.md) and [SPU validation](docs/spu-validation.md): audio-clocked guest kernels, PCM output, browser transport, and acceptance evidence.
- [Benchmark protocol](docs/benchmark.md): task families, agent environment, scoring, reproducibility, and evaluation integrity.
- [Implementation plan](docs/implementation-plan.md): work packages, ownership, dependencies, acceptance gates, and rollout.

The intended benchmark will measure architecture comprehension, constrained implementation, debugging, composition, timing, and resource tradeoffs. Results will identify both the model and its agent harness. The current executable prototype establishes the machine foundation rather than a calibrated leaderboard.
