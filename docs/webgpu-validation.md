# WebGPU acceleration acceptance

Implemented and checked on 2026-09-25 using the Codex in-app browser on an Apple M3 Max. The reference-engine results in [gpu-validation.md](gpu-validation.md) remain a separate historical measurement.

## Result

The full-detail 160×120 ray tracer runs at **approximately 60 presented FPS**. A three-second final sample advanced 180 frames in 3,000.4 ms. Across 180 observed dispatch timings, the median was **1.5 ms**, p95 **3.1 ms**, minimum **0.7 ms** and maximum **4.1 ms**. Timings include guest buffer upload, hardware execution and output readback; they exclude shader compilation and are not GPU timestamp-query measurements. Playback is paced at 60 Hz, so this is not an uncapped throughput result or a cross-device guarantee.

The earlier WASM browser run achieved about 18.3 FPS at this ray resolution. The accelerated kernel is compiled from the same 1,652-byte guest program, including its scene data. Its 228 instructions become 35 basic blocks. The image still contains the guest's moving point light, finite shadow rays, sphere-to-sphere and floor reflections, and three surface hits. There is no native host scene renderer.

The default quality is now full detail. `Auto` prefers WebGPU for eligible GPU programs; the renderer selector can force the WASM reference. Switching renderers resets the loaded cartridge and preserves playback state. Both quality modes remain available.

## Verification

- `npm test`: **51 Rust tests, 14 WASM integration tests and 5 GPU compiler tests passed**.
- `cargo fmt --check` and JavaScript syntax checks passed.
- **Eight browser hardware/fallback checks passed:** 65-invocation RGB888/tail handling; edited kernel constants; divergent branches and ROM loads; a non-unit sphere ray; bounds-error output rejection; finite termination of an infinite kernel; the real WASM worker running with WebGPU unavailable; and device-loss rejection.
- Manual viewer checks passed: automatic hardware selection, full-detail rendering, quality switching, pause, reset, eight frame steps, explicit WASM selection, and returning to accelerated playback.
- Adding a read from a writable binding to the ray kernel produced a visible fallback reason and continued rendering through WASM. Restoring the source restored acceleration.
- No browser warning/error entries were reported in the final viewer run. The full optional Chromium/WebKit Playwright suite was updated to request WASM for exact parity checks, but was not rerun for this milestone.

The optional hardware checks are reproducible in a secure browser context serving this repository:

```js
await (await import('./gpu-checks.js')).runGpuChecks()
```

They exercise real compute shaders. The unavailable-WebGPU check uses a separate disposable worker with that API hidden; it does not change the main viewer's capabilities.

## Identity and captures

The import-free WASM bridge is **176,886 bytes**, SHA-256 `6f41344969254f512923370b41ec4b4215583722e6ca92d3158925809f3be702`. Its reference rendering remains unchanged: at frame eight, full-detail WASM canvas RGBA SHA-256 is `75716a0e25e282ed83bfa3483b18e2dd8fd2d6e44c39b8ffe6db746cbe337408`, matching the earlier headless capture.

The accelerated full-detail canvas at frame eight has RGBA SHA-256 `5a8d81c12f011a31dc6cb1bdbe8fb4cda6a158d0deb197cf9ef429636561537c`. This is a local observation, not a portable golden hash. External dispatches charge zero virtual GPU ticks, so animation/presentation phase as well as floating-point behavior can differ at the same virtual frame number. The viewer explicitly shows fast math and host timing, with no virtual GPU-budget percentage.

The structured [validation record](../artifacts/webgpu-validation.json) also pins the compiler, runtime and worker file hashes. See [the backend contract](gpu-kernels.md#webgpu-acceleration) for memory restrictions, fallback behavior and timing differences.

## Practical limits

Kernels loading writable bindings use WASM. Overlapping writes to identical guest bytes have unspecified hardware order. Floating-point results and arithmetic faults intentionally differ from the reference. Byte stores retain neighbouring bytes through bounded atomic masked updates. A hardware error flag discards all pending output before WASM fallback.

Hardware execution is bounded by an 8,192-instruction per-invocation budget, a 4,096-attempt byte-store retry cap, and a worker cap of 64 accelerated submissions per virtual frame. Adapter/device requests each have a three-second deadline, shader compilation a 15-second deadline, and dispatch readback a two-second deadline. Compile/readback timeout destroys the accelerator and resumes the pending job in WASM. The cache holds at most eight pipelines. These host limits complement the browser's WebGPU validation; they do not claim canonical GPU timing.
