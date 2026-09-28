# Programmable SPU acceptance

Implemented and checked on 2026-09-25 on macOS with the Codex in-app Chromium browser and Node v24.16.0. The normative programming interface is [spu-1](../spec/spu-1.md).

## Implemented model

The SPU schedules ordinary `g.*` compute kernels on the audio clock. Its device state contains bindings, uniforms, bounded execution state and a PCM queue. Synthesis, sample access, envelopes, filtering and mixing are guest algorithms. Persistent state occupies guest RAM; one invocation can loop over time for feedback, while independent sample computations can run in parallel. No sound-specific opcode or fixed voice architecture was added.

Cartridge version 3 adds the SPU to CPU/GPU/video. It retains the 4,096-byte payload and 128 KiB RAM limits. Each block produces 256 stereo float frames at 48 kHz. The reference interpreter permits 65,536 compute ticks per block. WebGPU compiles the same binary ISA and supports reads from an invocation's writable state. Hardware floats and cross-invocation execution order are intentionally noncanonical.

## Reference capture

```sh
npm test
npm run capture:audio -- --frames 480
```

The [Signal garden cartridge](../examples/signal-garden.asm) is **1,400 payload bytes** including code and tables. Its guest kernel performs wavetable interpolation, a melody, bass/chord arithmetic, a two-tap noise filter, envelopes and stereo routing. A CPU program paints and animates the screen. There are no external audio assets.

The eight-second capture contains **384,000 stereo sample frames**, 1,500 complete blocks and zero queue overruns. Peak amplitude is **0.4972541**, RMS is **0.1075659**, and mean absolute left/right difference is **0.0291279**. All samples are finite. Reference execution plus PCM collection took about **534 ms** on this host; this is a single local observation, not a cross-device performance guarantee.

Artifacts: [WAV](../artifacts/signal-garden.wav), [PNG](../artifacts/signal-garden.png), [cartridge](../artifacts/signal-garden.db32), [capture report](../artifacts/signal-garden.json). WAV output is signed 16-bit PCM derived from the canonical float samples.

| Identity | SHA-256 |
| --- | --- |
| Import-free WASM, 192,044 bytes | `8fbac8f8ef7771c0522d05b2d928c760b52075b21c513f9546617184dded0780` |
| Raw interleaved float PCM | `dee4e7fc3e42f3a35f0595fc4a9914a5664d74cf7029edc2fb869fbd0f99c509` |
| WAV | `6bcfeffcb47b03d5bc8ca2adf8bf192e6d2e4018abf9f78cb6f0b4575fac48b7` |
| Final frame RGBA | `d62d4335216039c3f37b19ba9b6691e58241f5f37ddab201c1806b5f11d98e18` |

## Verification

`npm test` passed **63 Rust tests, 16 WASM integration tests, 6 compiler tests and 5 PCM transport tests**. Coverage includes generic state recurrence, finite/clamped output, bounded infinite kernels, invalid descriptors, profile gating, active GPU lease conflicts, clocked silence, bounded neglected queues, exact PCM across different host slices, and SPU completion before simultaneous scanout. The WASM remains import-free with a 16 MiB memory cap.

**Eleven real WebGPU checks passed** through `web/gpu-checks.js`, including all prior rendering checks plus persistent read/write state across dispatches, within-invocation reads after stores, finite SPU PCM in the real worker, deliberately corrupted hardware PCM falling back before publication, and GPU/SPU operation with WebGPU unavailable. These use disposable workers and do not modify the viewer's capabilities.

```js
await (await import('./gpu-checks.js')).runGpuChecks()
```

The final viewer build played **2,109,312 output frames (43.94 seconds)** through a running 48 kHz AudioContext with zero underruns, playback drops or SPU overruns. Its SPU backend reported WebGPU and the viewer maintained approximately 60 FPS. A separate reference-WASM playback run exceeded three minutes without underruns. These are presentation observations, not canonical hardware hashes or an acceleration comparison; dispatch/readback overhead can outweigh the work of a small audio kernel.

Manual controls passed: muted startup, explicit Sound on, pause/flush, silent frame stepping, resume with a fresh epoch, reset to zero sample time, renderer switching, and switching to a legacy cartridge disabling audio. The final main viewer reported no warning/error logs. The optional full Chromium/WebKit suite was not rerun, and physical speaker audibility was not independently verified.

## Playback and remaining scope

AudioWorklet only transports PCM. Its queue is bounded to 7,200 input frames (150 ms), starts after 2,304 frames (48 ms), and linearly resamples to the actual output rate. The initial 16 ms prebuffer suffered one short underrun during testing; 48 ms passed the observed runs. Tests cover 44.1 and 96 kHz conversion. Browser throttling or a kernel slower than real time may still underrun; silence and counters expose that condition without altering guest synthesis time. The implementation follows the [Web Audio processing model](https://www.w3.org/TR/webaudio/).

There is one kernel dispatch per block. Stateful algorithms must own their writable ranges; there is no cross-invocation barrier, multi-pass audio graph, hardware equivalence guarantee, or automatic synthesis/filter library. Those can be considered separately without changing the generic ISA model. DMA, general interrupts, snapshots, Wasmtime and scored benchmark evaluation remain separate future work.
