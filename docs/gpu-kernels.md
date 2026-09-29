# Programmable GPU: gpu-1

The implemented [gpu-1 contract](../spec/gpu-1.md) adds a programmable GPU to the CPU/video `bootstrap-1` profile. [spu-1](../spec/spu-1.md) adds an audio-clocked processor that executes the **same binary `g.*` ISA**; it has no audio-specific synthesis opcodes. Both use counted cartridge bytes and the same import-free WASM module. There is no host scene renderer or fixed sound synthesizer. [SPU validation](spu-validation.md) tracks audio evidence.

## Architecture chosen for ray tracing

The earlier eight-lane, integer-only proposal was suited to short procedural pixel kernels. Ray tracing needs vector math, square roots, division, repeated intersection tests, and lane-dependent paths. The first GPU therefore has 64 lanes per wave, 32 raw 32-bit registers per lane, binary32 arithmetic, vec3 operations, and deterministic execution of lanes sharing a program counter. Each invocation can branch independently. Code, register state, work limits, bindings, uniforms, and memory accesses remain bounded.

| Facility | Purpose |
| --- | --- |
| Integer arithmetic and bit operations | IDs, indices, loops, packed data, procedural effects |
| Scalar binary32 arithmetic and comparisons | Distances, material weights, visibility decisions |
| Vec3 add/subtract/scale/dot/normalize/reflect | Camera rays, hit positions, normals, reflected directions |
| Ray–sphere intersection | Return a geometric hit distance; kernels decide nearest hit, occlusion, material, and bounce |
| Checked scalar/byte loads and stores | Guest-defined scene data, output buffers, multipass algorithms |
| RGB888 store | Convert three linear register values to bytes; no shading or geometry |
| Lane-local branches and finite dispatch budget | Different rays can follow different paths without an unbounded call stack |

The geometry operation is deliberately small: it intersects one ray with one sphere supplied in registers and returns a distance or miss. It does not traverse a scene, find a material, cast a shadow, reflect a ray, or write a pixel. A kernel can instead implement its own primitive using arithmetic. Triangle/AABB operations and acceleration structures are possible future extensions; there is no baked-in three-sphere scene or ray-tracing service.

Binary32 allows compact, inspectable ray kernels without shipping software square-root/division routines in every cartridge. The reference rejects nonfinite arithmetic, fixes evaluation order, and uses no fused operations or fast-math. Normalization and intersection are instruction semantics, not unspecified host approximations. See the contract for precise encodings, costs, arithmetic, and failure rules.

## Dispatch, ownership, and presentation

The CPU programs one bounded dispatch through GPU MMIO: immutable ROM kernel, a two-dimensional grid, four disjoint checked buffer bindings, and sixteen latched uniforms. Read/write bindings must be in guest RAM. While busy, their memory is inaccessible to the CPU; read-only bindings prohibit CPU writes. This removes CPU/GPU data races. The video controller remains an observer, so the demo uses double-buffered RGB888 output and vblank page flips. The SPU has its own MMIO and launches a shared-ISA kernel at each 65,536-tick audio block event, writing 256 stereo binary32 frames into checked guest RAM. Persistent DSP state occupies ordinary read/write bindings.

The central machine clock orders CPU commits, GPU commits, SPU block events, and scanout in that order at equal ticks. GPU instructions consume explicit virtual ticks; a host run slice can end in the middle of an instruction without exposing its pending effects. Reference SPU work is an atomic block event with a 65,536-compute-tick quota and does not advance the central clock. GPU completion wakes WFI in gpu-1/spu-1; SPU blocks do not. General vectored interrupts remain a later device.

All lane reads precede writes for an instruction. Conflicting stores have a defined ascending-lane order. Later waves observe earlier waves. The reference can therefore execute deterministically in a single WASM worker while retaining a kernel programming model.

## Real-time acceptance

A 60 Hz virtual frame lasts 204,800 ticks. Report full dispatch duration, completed invocations, and presented frames. For real-time ray tracing, a full 160×120 dispatch must fit this interval and the host must execute and present the workload sufficiently quickly. Virtual throughput alone is not a wall-clock FPS claim.

Keep the CPU ray tracer as a baseline and the GPU ray tracer as a separate cartridge. Validate actual ray reflections and finite shadow segments, deterministic captures, frame-varying scene input, safe page flips, tail lanes, malformed code, buffer bounds, leases, and unfinished instruction effects. Record module hash and host engine with performance evidence. Detailed implementation acceptance belongs in [gpu-validation.md](gpu-validation.md).

## WebGPU acceleration

The browser lowers actual `gpu-1` and `spu-1` cartridge bytes to WGSL compute shaders. DB32 retains its own ISA; the backend contains no sphere-scene renderer, fixed synthesizer, or source-name special case. Edited assembly is assembled in WASM and its validated binary kernel is compiled again. All 43 opcode forms are supported, subject to the buffer rules below. The ray tracer's 228 instructions become 35 straight-line basic blocks in a bounded PC state machine. Pipelines are cached by exact code and binding configuration (at most eight entries).

`Auto` prefers WebGPU for GPU cartridges; `WASM` explicitly selects the reference; `WebGPU` requests acceleration with graceful fallback. The CPU, assembly, RAM authority and video scanout stay in WASM. The default ray tracer now uses full-detail 160×120 rays. The lower-resolution quality setting remains available.

| Component | Responsibility |
| --- | --- |
| `web/gpu-compiler.js` | Validate/decode binary kernel, form basic blocks, emit native WGSL math and checked memory operations |
| `web/gpu-webgpu.js` | Device, bounded pipeline cache, upload, compute dispatch, error flags, output readback |
| `web/machine-worker.js` | Serialize asynchronous work, service yielded GPU/SPU jobs, fallback, PCM transport and host measurements |
| `db-gpu` / `db-spu` / `db-wasm` external bridge | Validate dispatches and bindings, expose latched descriptors, yield/resume the machine |

Each compute invocation receives its own registers and follows the kernel's branches. Native `dot`, `normalize`, `reflect`, `sqrt` and `inverseSqrt` prioritize speed. Float rounding, fusion, saturation edges, nonfinite behavior and signed zero need not match the reference. This is intentional. WGSL permits implementation-dependent accuracy within its rules: [WGSL floating-point specification](https://www.w3.org/TR/WGSL/#floating-point). Compute submission and buffers follow the independent [WebGPU API](https://www.w3.org/TR/webgpu/).

### Memory and limits

The host stages a fixed 192 KiB mirror of the guest address space: counted ROM at zero, RAM at 0x10000. There are four shader bindings: immutable input words; atomic output words; 80 bytes of grid/uniform parameters; and a four-byte error flag. These are host implementation buffers, not extra guest-addressable memory. Only bytes in the guest's validated writable descriptors are copied back to WASM RAM.

For GPU preview, loads must use read-only guest descriptors. Kernels that read a writable binding fall back to WASM, including statically unreachable such instructions. SPU preview opts into atomic word/byte loads from writable descriptors so an invocation can read its own persistent DSP state and output. Read-only SPU loads still use the immutable input mirror. Byte/RGB888 stores use atomic masked updates, preserving neighbouring bytes shared by adjacent pixels; word stores are atomic. Hardware atomics do **not** define ordering between invocations with dependent reads/writes. Such kernels need the WASM reference or explicit phases/blocks for canonical results. No guest atomics or synthesis/drawing opcodes were introduced.

Every access checks its descriptor bounds. Each invocation has a conservative termination guard, charged per basic block: **1,048,576 instructions for GPU jobs and 65,536 for SPU jobs**. Every reference instruction costs at least one compute tick, so every invocation in a reference-valid job fits this guard. The bound is not divided by grid size or wave count, because work can be uneven or divergent. The worker identifies the processor explicitly, and pipeline cache identity includes it. There is no separate 8,192-instruction authoring limit. These counters bound hardware work; they do not reproduce the reference's whole-dispatch tick accounting.

Tail invocations exit before memory access. A bounds/budget flag discards the entire hardware result. The worker caps accelerated submissions at 64 per virtual frame before falling back. Missing adapters, device loss, compilation errors and unsupported kernels also fall back. Fallback resumes the original pending GPU or SPU job in WASM before accelerated output is published. SPU output is then validated and queued as the same 256-frame stereo PCM format.

### Scheduling and evidence

The additive host API enables external execution explicitly. A validated GPU START yields at its CPU commit tick, after any simultaneous video event. The machine is frozen during hardware work. The host copies successful output and completes the GPU at that same virtual tick, releases leases, and resumes the CPU; a directly following WFI consumes the completion wake. External completion charges **zero virtual GPU ticks**. This avoids interpreting the kernel a second time just to calculate canonical cost.

Consequently, dispatch duration, partial framebuffer visibility and fault side effects are intentionally different from reference execution. The viewer displays host dispatch wall time (upload + execution + readback, excluding compilation) and playback FPS. It hides the virtual GPU frame-budget percentage. WASM continues to define canonical benchmark captures and timing; accelerated pixels are preview output. Readback keeps the existing video path, source editor, PNG export and cartridge export working.

[WebGPU validation](webgpu-validation.md) records actual hardware results. Later optimizations can remove more readback, specialize independent outputs, use timestamps for compute-only timing, or lower more control flow into structured shaders. These do not require changing the guest ISA.

For audio, [spu-1](../spec/spu-1.md) defines the 48 kHz block clock, uniforms, work quota and PCM rules. [SPU validation](spu-validation.md) separates canonical WASM PCM and WAV capture from WebGPU kernel execution, AudioWorklet transport, and physical listening. Browser playback starts muted until **Sound on**; transport metrics alone do not prove audible output.
