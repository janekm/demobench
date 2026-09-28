# Benchmark protocol proposal

## 1. What a result means

The unit of evaluation is **model + agent harness + tool access + budget + task + machine version**. A capable model with a weak debugger workflow can differ from the same model with a stronger harness. Record both instead of calling every result a model-only score.

The benchmark should reveal whether an agent can:

- Learn unfamiliar documented CPU/kernel ISAs and a device model.
- Turn an audiovisual brief into an executable artifact.
- Budget code size, memory, compute, drawing time, and synchronization.
- Inspect failures and improve its program.
- Produce deliberate motion, visual composition, and sound under constraints.

Separate the guest's memory constraint from the agent's context/token budget. Both matter, but they are different experimental variables.

## 2. Task families

| Family | Example | Main evidence |
| --- | --- | --- |
| Foundational construction | Moving colour bands using a palette and vblank | Motion, colours, timing, correct execution |
| Mathematical effect | Kernel-based field, procedural texture, rotating wireframe, particle simulation | Spatial/temporal behavior and visible quality |
| Audiovisual composition | Three scenes with transitions and timed musical events | Scene coverage, rhythm, synchronization, coherence |
| Repair | Fix a demo with an interrupt or framebuffer ownership bug | Published required behavior and deterministic regression checks |
| Optimization | Fit a supplied effect below a smaller payload or runtime allowance | Preserved output requirements and measured savings |
| Specification transfer, later | Adapt to a separately documented machine variant | Successful adaptation under a separately reported protocol |

Foundational cases double as public learning material; do not count a tutorial copied verbatim as a strong benchmark success. Conformance tests validate the machine and toolchain and have their own pass/fail suite; they are not creative quality scores.

For the pilot, author 12 evaluated tasks: four effects, four compositions, two repairs, and two optimizations. Keep public tutorials and development tasks separate. Before a public ranking, expand and validate the suite, split it by effect/brief family rather than tiny wording changes, and ensure several examples in every claimed capability category.

### Example brief

> Produce a 12-second, looping 160×120 demo in at most 4,096 payload bytes. Begin with an indexed-colour starfield, transition to a rotating geometric object, and end with a full-screen RGB888 colour effect. Include three audible accents at 3, 6, and 9 seconds, each aligned to a visible event within two frames. First visible content must appear within 0.5 seconds. Use no external assets. Avoid an abrupt audiovisual discontinuity at the loop boundary.

The agent gets the full requirements and tolerances. Exact assessment frames or additional randomized seeds may be private, but they may only test declared behavior. A loop requirement must specify whether the guest continues naturally or is reset; prefer continuous execution and inspect both sides of the required boundary.

This example deliberately exercises several subsystems. Simpler tasks should isolate one or two skills so failure attribution remains possible.

## 3. Agent workspace and tools

Provide the manual, register map, CPU/kernel instruction reference, small programming examples, assembler, disassembler, deterministic WASM runner, and documented preview tools. Agents may read the public core source in an explicitly named open-source track; private task material and grading code remain outside their workspace. Freeze this visibility policy for every reported comparison.

Proposed tools:

- `assemble`: source to cartridge, symbol map, listing, and payload-size report.
- `run`: execute a chosen number of virtual frames and return diagnostics and metrics.
- `capture`: selected frames, contact sheet, and a bounded audio/video clip.
- `inspect`: CPU PC/registers, GPU kernel/wave/lane registers and predicates, memory ranges, MMIO, pending IRQs, engine leases, and counters.
- `trace`: bounded events around a chosen frame, tick, or fault.
- `submit`: freeze one final cartridge plus source/build provenance for clean evaluation.

All development and final execution use the same pinned authoritative WASM module. The browser and headless hosts differ only in their presentation/orchestration roles. A public preflight checker reports compliance and declared simple requirements. Private assessment does not give unlimited feedback on hidden scoring criteria.

The agent can use scripts to generate source/data during authoring, but every runtime byte must fit in the submitted payload or be produced by the guest. CPU code, GPU kernels, generated lookup tables, precomputed frames, and compressed assets all count. A task may expressly permit assets; otherwise the examples and brief should encourage procedural construction.

Use a clean per-attempt authoring sandbox with pinned tools and no network by default. Final cartridges execute in a separate trusted runner against immutable machine and task definitions. The agent cannot replace the evaluator binary, edit validators, or submit a video instead of executable code. Resource-limit and isolate the host process too: the VM language boundary alone does not contain implementation bugs or hostile build scripts.

## 4. Budgets and experimental tracks

Keep these budgets separate:

| Budget | Meaning |
| --- | --- |
| Payload bytes | Final guest program and embedded data |
| RAM capacity | Total mapped mutable memory, including surfaces and audio tables |
| Virtual duration/throughput | Fixed simulated CPU/GPU hardware, dispatch work cap, and observation interval |
| Model usage | API input/output/reasoning accounting as available |
| Agent actions | Model turns and tool invocations |
| Preview allowance | Cumulative virtual frames rendered during development |
| Wall time | Operational safety cap, reported separately from virtual execution |

The runner must not let a single tool request render an unbounded number of previews. A stalled host process is an infrastructure issue to investigate; an oversized payload or deterministic guest fault is a submission failure.

Pilot hypothesis: 20 minutes per attempt, a fixed 24,000 reported generated-token cap where the provider exposes/enforces it, at most 80 tool calls, and at most 7,200 cumulative preview frames. These are starting values for calibration, not settled scientific defaults. Record unavailable usage as unavailable; do not imply equivalent reasoning compute across providers with incompatible accounting.

Start with one fixed harness, one feedback policy, and three independent attempts per task. Use best-of-N only in a clearly labeled separate track; the primary result averages independent attempts without picking the best. Later compare full agent systems in a separate harness-open track.

Audio/video-capable feedback and image/text-only feedback must be different tracks. An agent that cannot consume audio should not be silently treated as having the same tools. Measure one-shot versus iterative performance as a useful secondary ablation, with separate budgets and reporting.

Do not mix 4 KiB, 8 KiB, and 16 KiB entries in one ranking. Larger limits are useful development profiles, but they change the task. A CPU-only bootstrap profile and the programmable-GPU profile likewise have separate identities and results.

## 5. Scoring without a misleading single number

Use three visible layers:

1. **Validity:** loads, fits its profile, stays within declared rules, and runs the required interval without faults. Invalid submissions count as failures, with their reason retained.
2. **Requirement satisfaction:** observable task-specific behaviors, with published tolerances. This may be partly automatic and partly blinded rubric review.
3. **Presentation quality:** visual composition, motion, transitions, audio arrangement where applicable, and audiovisual coherence.

Resource efficiency is reported alongside these as a Pareto comparison: payload bytes, frame/engine timing, and relevant working-memory declarations. Do not use host execution speed as guest efficiency. A unified RAM machine always has the same capacity; a high-water write address is not a trustworthy measure of actual live memory use.

Exact RGB/PCM hashes are appropriate for conformance and strict preservation tasks, not for deciding whether two creative solutions are equally good. Automated creative checks can measure scene coverage, accent timing, palette usage, continuity, and task-specific geometry. Test validators against counterexamples such as blank output, noise, strobing, or satisfying a pixel statistic without depicting the requested effect.

Do not turn raw entropy, motion magnitude, colour count, or image similarity into a general aesthetic score. They are diagnostics, not proxies for successful art direction.

For presentation quality, use anonymous pairwise comparisons or an anchored rubric with randomized order. Humans should calibrate the judgments. A fixed multimodal judge can assist after validation against human review; publish judge identity/configuration, prompt, agreement, and uncertainty. Use full clips and representative temporal coverage rather than a single chosen screenshot. Normalize playback conditions consistently, but retain raw audio for technical checks.

Treat captions and other submission content as material being judged, never as instructions to the judge. Limit disclosure of model identity and author claims during review.

Report validity rate, requirement pass rate over **all** attempts, requirement detail, conditional quality among valid attempts with its denominator, and resource/cost distributions. Show per-family breakdowns, repeated-run variance, and confidence intervals clustered at least by task. Avoid ranking systems whose differences are within uncertainty. The pilot need not publish a composite score; if one is later required, preregister its weights and how invalid attempts contribute before collecting ranking data.

## 6. Reproducibility and release discipline

Every run should record:

- Machine/profile identifier and content hash; exact WASM module hash, host runtime identity, ABI version, and core/toolchain commit/build identity.
- Task version, public brief hash, evaluation seed, observation interval, grader version, and evaluation configuration.
- Model identifier/snapshot when available, provider, sampling parameters, harness version, tools, permissions, and budgets.
- Attempt ID, full action trajectory subject to provider visibility, usage accounting, timestamps, and infrastructure errors.
- Submitted source, deterministic build recipe, exact payload bytes/hash, and final-cartridge selection time.
- Canonical raw RGB frame stream and signed-16-bit PCM stream hashes; accessible clips/contact sheets; machine metrics and relevant trace.
- Validity outcome, requirement results, quality judgments, and supporting evidence references.

Store raw capture streams once per cartridge/seed/machine identity and derive presentation encodes from them. Compressed video/audio encoders are not the reference execution format. Evaluation reruns must start from clean reset, not the agent's last preview snapshot.

Use submission time and a content hash to prevent replacement after scoring. Retry transient infrastructure failures under a published bounded policy, without granting extra successful development attempts. Never silently resubmit model work because a job's submission status was ambiguous.

A novel ISA reduces direct reuse of existing target-specific solutions, but it does not establish contamination freedom. Once published it can appear in training data. Keep held-out task families, version releases, retire exposed evaluation tasks, and report model release dates. Do not rely on arbitrary opcode shuffling as the primary benchmark; it can mostly measure assembly translation. Fully documented variant adaptation is a separate research track.

## 7. Benchmark acceptance

Before trusting rankings:

1. Demonstrate feasible hand-written baselines for every task under the actual limits.
2. Include weak baselines and adversarial near-misses that must fail relevant requirements.
3. Verify byte-identical raw captures from the same WASM module in supported browser engines and headless Wasmtime, and uninterrupted versus snapshot-resumed runs. Native developer builds are supplementary checks, not the scoring runtime.
4. Run a small model pilot, inspect failure causes, and revise ambiguous tasks before freezing the evaluated release.
5. Validate quality judgments against blinded human judgments and disclose disagreement.
6. Publish the exact protocol, reproducible artifacts where releasable, and remaining limitations.

The canonical runner and trace/result format should be framework-independent. An adapter to an established evaluator can manage model calls, experiments, and logs without owning VM semantics. [Inspect AI](https://github.com/UKGovernmentBEIS/inspect_ai) is one candidate. [Inspect Evals' reproducibility guidance](https://github.com/UKGovernmentBEIS/inspect_evals/blob/main/BEST_PRACTICES.md) specifically supports pinning source and environment identities rather than depending on mutable defaults.
