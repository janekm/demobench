# Implementation and agent work plan

## Implemented CPU/video, GPU, and SPU milestones

The repository has a working CPU, checked memory bus, exact scheduler, CPU/kernel assembler, 64-lane programmable GPU, audio-clocked SPU, all five video formats, browser viewer, and Node headless video/audio capture. They run in one WASM module. `bootstrap-1` contains CPU/video; `gpu-1` adds GPU MMIO; `spu-1` adds generic audio jobs using the same `g.*` kernel ISA. The browser can compile eligible GPU and SPU jobs into WebGPU compute shaders for fast preview, with WASM fallback and deliberately different float/timing behavior. DMA, full IRQ/timer support, snapshots, Wasmtime embedding, and scored evaluations remain deferred. The [SPU contract](../spec/spu-1.md) and [validation](spu-validation.md) define the audio implementation and evidence.

The bootstrap uses Node's WebAssembly embedding for headless capture; the planned Wasmtime adapter is still future work. [The bootstrap contract](bootstrap-contract.md) and [README](../README.md) describe the runnable system. The milestones below describe the broader target rather than a claim that every full-profile M0/M1 interface has been implemented.

## 1. First freeze the seams

Parallel agent work becomes useful after the shared contracts exist. Otherwise every device invents its own timing, error handling, memory access, and tests, and integration becomes a redesign.

One architecture/integration owner should initially produce:

- A short normative machine manual and explicit open-decision list.
- Machine-readable CPU/kernel ISA, dispatch, MMIO, cartridge, fault, and profile schemas.
- Bus, device, scheduler, lease, interrupt, observer, and snapshot interfaces.
- Shared pixel-format helpers and integer arithmetic rules.
- A minimal crate/package graph with stub devices, a shared WASM host ABI, and browser/headless smoke checks.
- Hand-audited conformance vectors, a mock bus, and a deterministic device test clock.

Before future implementation fans out, settle instruction encodings, reset state, MMIO offsets, atomicity, same-tick ordering, leases, scanline/palette behavior, interrupt timing, kernel masks/bindings/store ordering, and per-operation costs. The SPU's audio clock, binary32 PCM format, guest synthesis model, 65,536-tick work quota, and output draining are specified in [spu-1](../spec/spu-1.md). DMA and full IRQ/timer contracts still need separate freezes.

The owner approves and versions shared contract changes. Component agents may propose changes; they may not silently patch another component's API or invent alternate timing rules. Other agents can draft independent task briefs and UI wireframes during contract work, provided they do not assume unapproved runtime interfaces.

## 2. Proposed repository layout

```text
spec/
  machine.yaml              # Profile, address space, reset values, timing
  isa.yaml                  # CPU encoding and decode metadata
  kernels.yaml              # GPU ISA, dispatch and buffer-binding contracts
  devices/*.yaml            # Registers, access rules, command layouts
  formats/                  # Cartridge, trace, result and snapshot schemas
  semantics/                # Normative behavior and worked examples
crates/
  db-contracts/             # Shared types and generated definitions
  db-core/                  # CPU, bus, leases, scheduler, interrupts, timers
  db-gpu/                   # Kernel interpreter, lanes, predicates and bindings
  db-dma/                   # Transfers and blitting
  db-video/                 # Pixel formats and canonical scanout
  db-spu/                   # Generic audio-clocked kernel jobs and PCM queue
  db-asm/                   # CPU/kernel assembler and disassembler, size report
  db-wasm/                  # Composition root and shared machine.wasm host ABI
  db-runner/                # Headless Wasmtime host, capture and resource limits
web/                       # Preview, editor integration and debugger
benchmark/
  protocol/                # Public task and result formats
  harness/                 # Agent adapter, attempt budget and submission logic
  validators/              # Public preflight and general validator library
  tasks/public/            # Tutorials and development tasks
  baselines/               # Releasable hand-written examples
tests/
  vectors/                 # Hand-audited golden cases
  integration/             # Cross-device edge cases and demo fixtures
  differential/            # Browser/Wasmtime/snapshot parity
docs/                      # Design, author manual, contribution contracts
```

Private tasks and their expected results live in a separate evaluator-controlled store, not in the agent workspace or a supposedly hidden subdirectory of this checkout. Generated files identify their source; agents edit the source definitions, not generated copies.

Avoid circular dependencies: shared contracts and pixel codecs sit below devices; `db-core` defines runtime timing; `db-wasm` is the machine composition root that wires implementations together. Device interfaces live in `db-contracts`, which has no concrete implementations. Core does not import concrete devices that already depend on core. All devices link into the single authoritative WASM module; modular source ownership does not require separate WASM instances.

## 3. Bounded work packages

| Package / owner | Owns | Consumes | Required completion evidence |
| --- | --- | --- | --- |
| A — architecture/integration | `spec/`, shared contracts, integration fixtures, release identity | Product decisions and prototype feedback | Reviewed contract set including kernel/WASM ABI, hand-audited vectors, runnable stub composition |
| B — CPU/runtime | `db-core` | Frozen ISA, bus/device contracts, event rules | ISA/fault vectors; timers/IRQs; lease enforcement; same-tick tests |
| C — toolchain | `db-asm` | CPU/kernel encoding and cartridge schemas | Browser/headless authoring WASM, round-trip listing/disassembly, symbol maps, combined payload accounting, executable fixtures |
| D — GPU kernels | `db-gpu` | Kernel ISA, bus/lease/dispatch contracts, pixel types | Lane/mask/memory vectors, metered loops, dispatch IRQs, kernel diagnostics |
| E1 — DMA/blitter | `db-dma` | Bus/lease contracts, shared surface/pixel types | Exact transfers/blits, timing, packed formats and bad-range rejection |
| E — video | `db-video`, shared pixel codecs by initial agreement | Memory view, clock, IRQ and observer contracts | All formats, palette changes, page flips, scanline timing, frame hashes |
| F — SPU | `db-spu` | Shared `g.*` ISA, audio clock, bindings, PCM output contract | 256-frame block/timeline counts, 65,536-tick work bound, finite/clamped stereo PCM, conflicts and queue limits |
| G — WASM embedding and UI | `db-runner`, `db-wasm`, `web/` | Core control/capture/snapshot APIs, cartridge validation | Same module in worker/Wasmtime, bounded imports/memory/output, CPU/kernel debugging and parity |
| H — evaluation protocol | `benchmark/`, external private task packaging | Stable runner/result protocol and manual | Clean attempts, budget enforcement, baselines, validators, reproducible reports |

This is logical ownership, not a requirement to run every owner concurrently. B–F can proceed against stubs after A's first gate. E1 can initially be combined with E or B if staffing is limited; keep GPU kernel implementation a distinct assignment. G should start with the shared WASM module and minimal headless/browser hosts, then add the richer UI. H can author briefs early but cannot calibrate difficulty without a functioning machine.

Each task handoff should include exact owned paths, allowed dependencies, contract version, deliverables, conformance vectors, integration command, non-goals, and a decision deadline. Require a small working example and reproducible evidence with each component. Use isolated branches/worktrees and integrate small increments. Shared manifests, schemas, and lockfiles remain coordinated by A.

The component author should not be the only reviewer of its edge semantics. Cross-review video/pixel packing against GPU stores, CPU/kernel decoders against assembler, and audio against scheduler. The integration owner accepts actual behavior, not just a component's reported test pass.

## 4. Milestones and acceptance gates

| Milestone | Scope | Acceptance gate |
| --- | --- | --- |
| M0 — executable contract | CPU/kernel encodings, registers, semantics, shared WASM ABI, stubs, fixtures | All shared interfaces build; byte encoding, MMIO, kernel dispatch and timing examples agree |
| M1 — minimal visible WASM machine | Assembler, CPU, memory, interrupts/timers, indexed scanout, basic browser/headless hosts | A ≤4 KiB program animates a palette effect for 720 frames; identical module/captures in browser and Wasmtime |
| M2 — video and programmable audio | All pixel formats and the `spu-1` guest-kernel SPU; DMA remains a later device | Page flips and RGB888 pass; audio-clocked 256-frame stereo PCM, bounds, queue behavior, reference capture and browser transport have separate evidence |
| M3 — programmable micro-GPU | Kernel assembler, 64-lane PC-cohort interpreter, vector/intersection math, bindings, timing and telemetry | Gradient/procedural/particle kernels execute within limits; bounds, masks, contention and dispatch IRQ tests pass |
| M4 — usable authoring loop and pilot | Rich browser debugger, trace, snapshots, 12 tasks, human baselines, repeated attempts | Agent repairs a deliberate CPU/kernel bug; resume parity holds; tasks are feasible, bounded and scored with evidence |
| M5 — frozen public release | Calibrated machine/task/protocol versions and reviewed results | Reproduction package works independently; limitations and quality uncertainty are documented |

Critical integration path for the remaining benchmark work is **implemented CPU/GPU/SPU base → DMA/IRQ contracts if required → authoring pilot → frozen release**. The browser viewer and Node headless host already share a WASM vertical slice. Wasmtime, snapshots, richer debugging, and scored evaluation require their own acceptance gates. Model evaluation spend should start only after baselines demonstrate feasibility.

As a planning envelope, allow roughly 6–9 weeks with a consistent integrator and several parallel implementation streams: one to two for contracts/minimal WASM execution, two to three for devices and programmable-GPU integration, about one for authoring tools, and two to three for calibration/release. This is a scope estimate, not a measured schedule; benchmark validation may take longer than emulator coding. A CPU/video prototype should arrive well before the full profile.

## 5. Validation strategy

Build tests around externally observable behavior, especially boundaries where independently authored modules meet:

- CPU arithmetic overflow, signedness, immediates, alignment, branch targets, and invalid encodings.
- Instruction effects and device events at the same tick; masked/coalesced IRQs; correct interrupt return.
- Device completion exactly on a scanline or vblank, and SPU block work at multiples of 65,536 ticks.
- Argument changes while an engine is busy; lease conflicts; ROM source and MMIO destination rejection.
- Packed-pixel nibble/bit order, stride padding, blit clipping, and per-lane pixel-store merges.
- GPU tail-lane masks, uniform branches, instruction metering, bounded loops, code/buffer bounds, and read/write ordering.
- Palette changes immediately before and after a line capture; late page flips and reset video state.
- SPU uniform 14/15 time and rate, 256 interleaved stereo binary32 frames per block, finite/clamped output, 65,536-tick work quota, and bounded queue overruns. Phase, noise, envelopes, and filters belong to individual guest-kernel fixtures rather than device registers.
- Snapshot/resume during a multi-tick CPU instruction, GPU/DMA job, partial scanout, and interrupt handler.
- Cartridge header abuse, combined CPU/kernel payload accounting, out-of-bounds arithmetic, malicious descriptor sizes, and bounded capture.
- WASM import/export allowlists, maximum linear memory, bounded stepping/output queues, worker termination, and headless watchdog behavior.

Use property tests and fuzzing for decoders, loaders, and range arithmetic. Golden semantic cases must not all be generated from the same implementation being tested. Browser/Wasmtime equality checks portability, not independent correctness. Hand-calculated vectors and, where justified, a tiny independently written model provide the latter. Test more than one browser engine and validate exact module identity in the evidence.

For creative integration fixtures, keep exact hashes for a few stable canonical demos, but do not demand exact hashes from arbitrary benchmark solutions. CI publishes small contact sheets, audio snippets, trace summaries, and resource reports for review. Bound full-duration captures to selected integration jobs so ordinary edits remain cheap to check.

## 6. Decisions, risks, and stop conditions

| Risk / decision | Recommendation or response |
| --- | --- |
| ISA unfamiliarity becomes the whole test | Provide concise docs and small CPU/kernel examples; measure learning separately from composition |
| Fixed 32-bit encoding crowds out effects | Test several hand-written 4 KiB examples before v1 freeze; revisit encoding only then |
| GPU complexity delays the entire project | Ship the CPU/video prototype first; freeze a small kernel ISA and defer local memory and atomics |
| Peripheral integration drifts | Central scheduler, frozen contracts, boundary tests, one integration owner |
| RAM constraints are cosmetic | Allocate all buffers/tables in shared RAM and prohibit hidden asset stores |
| Audio costs more effort than useful signal | Use small guest-written `g.*` kernels and a subset of sound tasks; compare canonical PCM and assess judging quality before expanding scope |
| Visual scoring is easy to game | Publish requirements, test negative controls, calibrate blind judges with humans |
| WASM CPU/kernel interpreters are too slow for iterative use | Measure full-duration captures at M1/M3; optimize the module without changing guest semantics or switching the scored GPU to host WebGPU |
| Most agents fail before producing anything | Diagnose docs/tooling versus task difficulty before increasing hardware budgets |
| All agents trivially pass | Increase composition/optimization demands and held-out families before complicating the ISA |

The first useful deliverable is a tiny animated cartridge, exact headless capture, a memory/size report, and enough documentation for a second implementer to reproduce it. That proves the machine's foundation. The later pilot establishes whether the benchmark measures useful differences between agents.
