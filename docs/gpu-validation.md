# gpu-1 implementation acceptance

This is the reference-engine milestone record. The later [WebGPU acceleration acceptance](webgpu-validation.md) records the accelerated backend, its newer WASM bridge artifact, and changed default ray quality. Measurements below retain their original module identity.

Validated locally on 2026-09-25, on an Apple M3 Max running macOS arm64. This extends the historical [bootstrap acceptance](bootstrap-validation.md); it does not claim that the future complete machine or benchmark scoring harness is implemented.

## Implemented

The [gpu-1 contract](../spec/gpu-1.md) is implemented by `db-gpu`, the assembler, the central machine scheduler, and the browser/headless WASM hosts. Version-2 cartridges select this profile. Version-1 cartridges retain bootstrap-1 behavior, including faults on GPU MMIO.

The GPU executes 64-lane waves, 32 registers per lane, 43 opcodes, finite binary32/vector arithmetic, a ray–sphere geometric operation, lane-local control flow, checked buffer bindings, and deterministic memory effects. Dispatch completion wakes the CPU. GPU execution, CPU execution, and scanout share the virtual clock. Host slices preserve pending instructions, and a dispatch exceeding 1,048,576 ticks faults at its deadline.

The 1,652-byte ray-tracing cartridge includes CPU control, kernel code, and scene data. Its guest kernel traces three surface hits, finite shadow rays, sphere/floor reflections, specular highlights, and an animated point light. It uses two 57,600-byte RGB888 buffers and vblank page flips. The CPU only controls dispatch, uniforms, and presentation. The default traces 80×60 rays and fills 2×2 output blocks; the quality selector can use one ray per 160×120 output pixel.

## Artifact and tests

- Import-free `web/machine.wasm`: **172,925 bytes**.
- SHA-256: `31494e2f4579f7ccaa4b6300f9c8fce3a733d7ad3d037f53afdc3b85bd3e8b29`.
- `npm test`: **48 Rust tests and 14 WASM integration tests passed**.
- `cargo fmt --check`: passed.
- Browser checks used the Codex in-app browser against the localhost viewer. Quality changes preserved all source text except the selected constant; pause, reset, and eight frame steps worked. Both canvas captures exactly matched the Node headless host. No browser warning/error entries were reported.
- The optional full Playwright Chromium/WebKit suite was extended for both GPU modes but was not executed for this milestone. Earlier bootstrap browser results are separate evidence.

The tests cover opcode encoding, malformed code, literal/branch validation, nonfinite arithmetic, out-of-bounds accesses, read/write leases including CPU instruction fetches, tail lanes, divergent PCs, conflicting stores, instruction atomicity, pending effects, completion wakeup, exact budget exhaustion, unnormalized sphere rays, animated output, and deterministic replay. Existing CPU/video and CPU ray-tracing tests remain green.

## Performance

The virtual frame interval is 204,800 ticks. Virtual budget compliance and host throughput are different measurements.

| Mode | Rays | GPU ticks per dispatch | Maximum virtual frame budget | Node WASM FPS | Browser presented FPS |
| --- | ---: | ---: | ---: | ---: | ---: |
| Fast, default | 80×60 | 56,003–56,099 | 27.4% | 70.85 | 54.33 |
| Full detail | 160×120 | 202,203–202,335 | 98.8% | 19.10 | 18.33 |

Node v24.16.0 measurements use 16 warmup frames followed by 120 measured frames, with 120 completed dispatches in each measurement window. Only WASM execution time is counted; startup, assembly, frame hashing/readback, and UI presentation are excluded. Each run observed 32 distinct presented images over the light's animation cycle. The browser measurements count published frames over approximately three seconds while playing: fast advanced 163 frames in 3,000.4 ms, full advanced 55 in 3,000.9 ms. These are local observations, not cross-device guarantees or a sustained 60 FPS browser claim. Full-detail execution does not meet 60 wall-clock FPS on this host.

Raw Node results: [fast](../artifacts/gpu-benchmark-fast.json), [full](../artifacts/gpu-benchmark-full.json). Browser observations: [GPU browser record](../artifacts/gpu-browser-validation.json).

```sh
npm test
node scripts/bench-gpu.mjs --pixel-shift 0 --frames 120 --warmup 16 --out artifacts/gpu-benchmark-full.json
node scripts/bench-gpu.mjs --pixel-shift 1 --frames 120 --warmup 16 --out artifacts/gpu-benchmark-fast.json
node scripts/capture.mjs --demo gpu-ray-tracer --frames 8
```

## Exact browser/headless parity

Both captures are the published frame after eight calls stepping 204,800 virtual ticks, at machine tick 1,638,400. Hashes cover the raw 160×120 RGBA bytes, not PNG encoding. Full detail completes its initial dispatch later, so its completed-dispatch count is seven at this instant; fast has completed eight.

| Mode | RGBA SHA-256 | Capture |
| --- | --- | --- |
| Fast | `607ff11f94f570cc9ed8d27523d1b816796cfa760c2635448f3b0ab27f113abe` | [PNG](../artifacts/gpu-ray-tracer.png), [metadata](../artifacts/gpu-ray-tracer.json), [cartridge](../artifacts/gpu-ray-tracer.db32) |
| Full | `75716a0e25e282ed83bfa3483b18e2dd8fd2d6e44c39b8ffe6db746cbe337408` | [PNG](../artifacts/gpu-ray-tracer-full.png), [metadata](../artifacts/gpu-ray-tracer-full.json), [cartridge](../artifacts/gpu-ray-tracer-full.db32) |

The [full-detail source variant](../artifacts/gpu-ray-tracer-full.asm) differs from the bundled example only in `PIXEL_SHIFT` (zero instead of one).

## Remaining work

WebGPU acceleration was not implemented at this milestone. The subsequent [accelerated backend](gpu-kernels.md#webgpu-acceleration) now compiles eligible kernels to WGSL, deliberately relaxing numerical and timing equivalence for speed. WASM remains the reference for benchmark output and timing; see [the later acceptance record](webgpu-validation.md).

Audio, DMA, general vectored interrupts, snapshots, a GPU debugger, Wasmtime embedding, accelerated scene structures, and scored benchmark evaluation remain future work.
