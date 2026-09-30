# Packing experiments, 30 September 2026

The best experimental candidates save **516 bytes across eight recent
cartridges**, or 16–158 bytes per cartridge. These are complete runnable payloads:
decoder plus compressed stream, excluding the standard 32-byte header. All
application bytes and linked addresses are preserved. The experiments add no VM
features or host decompression. Production `pack.mjs` selection is unchanged.

## Results

| Frozen cartridge | Linked image | Existing packer | Best experiment | Saved | Free of 4096 | Method |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Koi | 6980 | 4061 | **3991** | 70 | 105 | Previous byte zero/nonzero + compact decoder |
| Pelican, 30 Sep | 8588 | 4045 | **3887** | 158 | 209 | Range-coded LZ + compact decoder |
| Pelican on a Bicycle | 6840 | 4094 | **4032** | 62 | 64 | Previous byte zero/nonzero + compact decoder |
| Lightcone | 6672 | 4071 | **4055** | 16 | 41 | Compact existing range decoder |
| Elsewhere | 6852 | 4084 | **4068** | 16 | 28 | Compact existing range decoder |
| Limit Set | 6968 | 4074 | **4040** | 34 | 56 | Previous byte zero/nonzero + compact decoder |
| Mega | 6752 | 4070 | **4013** | 57 | 83 | Previous byte zero/nonzero + compact decoder |
| Carpet | 6612 | 4093 | **3990** | 103 | 106 | Previous byte zero/nonzero + compact decoder |

The [frozen sources and pack reports](../tools/pack/research-fixtures/) are
included in this repository. Every linked image hash was checked against its
original pack report before testing. [Recorded results](../tools/pack/research-fixtures/results.json)
include candidate sizes, hashes and runtime parity evidence. These results apply
to the frozen revisions, including the Koi build in that corpus.

The search measured **211 candidates per cartridge, 1688 total**, in 18 reported
families (some separate compact and unmodified decoders). The existing packer's
31-candidate search was rerun for each baseline. This is a bounded experimental
search, not a globally optimal packing claim.

## Decoder machine code as compression context

The guest reads its own decoder instruction bytes from ROM and uses their bits
to train the same lane-specific probability trees that decode the image. The
encoder trains on those exact assembled bytes. No training data is stored twice.
The seeded prefix ends before the stream-end immediate, avoiding a circular
dependency between the compressed length and the seed bytes. Each report records
the prefix length and hash.

This implementation saved **1–9 compressed-stream bytes** relative to the best
unseeded range model for each cartridge. Its warmup code costs **148 additional
bytes** for the winning four-lane models: a net loss of **139–147 bytes** against
unseeded range coding. Decoder instruction shortening reduces that penalty but
does not produce a winner. The latest Pelican already favors LZ, so its gap to
the existing packer is larger still.

The finding is specific to this warmup model and corpus. Most image bytes are
GPU/SPU instructions and data; the seed is a short CPU decoder. This mismatch is
a plausible explanation for the small gain, not a separately isolated causal
result. Synthetic canonical-WASM tests cover seeded extraction, including
compact and unmodified decoder bytes. Oversize seeded candidates are measured
but cannot be delivered as valid 4 KiB cartridges.

## Other ideas tested

**Zero/nonzero previous byte context.** Split each of the four literal trees
according to whether the immediately preceding decoded byte was zero. Eight
trees use 4096 scratch bytes, cleared before handoff. This inexpensive distinction
fits the many zero fields in instruction words. Before decoder shortening it
saves 14–83 bytes on five cartridges. The compact version is the overall winner
on Koi, Bicycle, Limit Set, Mega and Carpet.

**Range-coded LZ.** Keep an ordinary DBLZ parse, but adaptively range-code the
literal trees, match flag, gamma length/distance bits and distance low bits.
Nine distance encodings and five adaptation rates were tested. Pelican's winning
variant uses a 520-byte decoder, a 3367-byte stream and 2404 scratch bytes. It
saves 158 bytes overall. On the other seven images the larger decoder costs more
than this hybrid recovers. The parser still minimizes DBLZ bit costs; an
entropy-aware parser is a useful next experiment, not something tested here.

**Shorten decoder instructions.** Replace two-instruction `li` pseudos with
single `addi` or `lui` instructions when the immediate is representable. This
also applies to known small ROM labels. Application code is untouched. The
ordinary four-lane range decoder shrinks from 352 to 332–336 bytes, depending on
load alignment. This accounts for the entire gain on Lightcone and Elsewhere.

**Richer contexts.** Tested previous-byte high/low bits, previous instruction
lane high bits, and the current word's opcode high/low bits, using 1–4 context
bits. Before shortening, previous-byte high bits save 3–67 bytes on five
cartridges. Opcode contexts help Carpet but do not beat its zero/nonzero model.
More context is not automatically better: sparse trees learn slowly and cost
additional decoder instructions and scratch RAM.

**Other negative results.** Per-lane adaptation rates, wider uniform rate
searches, and reversible byte-wise XOR/subtraction against the preceding word
do not beat the existing packer overall. Increasing the LZ match-chain limit
from 256 to 4096 saves only four bytes on Pelican. The existing packer already
tests byte-lane shuffling with LZ; this experiment did not add a second copy of
that search.

## Startup and memory tradeoffs

| Cartridge | Existing extraction, virtual ms | Best extraction, virtual ms | Best scratch bytes |
| --- | ---: | ---: | ---: |
| Koi | 114.19 | 119.69 | 4096 |
| Pelican, 30 Sep | 28.58 | 75.35 | 2404 |
| Pelican on a Bicycle | 112.11 | 117.50 | 4096 |
| Lightcone | 109.34 | 109.04 | 2048 |
| Elsewhere | 112.19 | 111.89 | 2048 |
| Limit Set | 114.04 | 119.56 | 4096 |
| Mega | 110.55 | 115.88 | 4096 |
| Carpet | 108.49 | 113.65 | 4096 |

These are counted guest ticks divided by 12,288 ticks/ms, not host wall time or
browser performance. Pelican makes the largest size/time tradeoff. Every
candidate reserves scratch at `0x10000`, disjoint from its frozen image, and
clears it before application entry.

## Reproduction and evidence

Requires the existing bundled `web/machine.wasm` and `tools/pack/linker.wasm` plus
Node.js 22+. No package install or engine rebuild was used for these experiments.

```sh
npm run test:pack
npm run test:pack:research
npm run research:pack
npm run bench:pack:research
```

To use the experimental search on a new RAM-only `dynamic-1` program:

```sh
npm run pack:research -- my-demo.asm -o artifacts/my-demo.db32 --load 0x2c000
```

This opt-in command also considers the production packer's result, retaining it
when the experiments cannot improve payload size. It can accept an image whose
baseline pack exceeds 4096 bytes if an experimental candidate fits. Temporary
scratch is fixed at `0x10000`; overlapping models are skipped. The selected
cartridge is verified on canonical WASM before writing the usual sidecars.

The default corpus manifest resolves the included frozen fixtures relative to
the manifest file. To use another corpus, pass an output directory and a JSON
manifest of entries with `name`, `source`, and `report` paths (relative to that
manifest):

```sh
node tools/pack/research.mjs artifacts/pack/my-research my-corpus.json
node tools/pack/research-runtime.mjs artifacts/pack/my-research
```

Snapshots are reused on reruns. Choose a new output directory to measure new
source revisions. The harness currently targets RAM-only `dynamic-1` images
whose source/report hashes match and which the baseline packer can pack.
Scratch-overlapping models are skipped. The corpus benchmark and single-source
experimental CLI are separate opt-in tools; the production CLI is unchanged.

The existing regression suite passes, including 840 codec round trips. Another
275 experimental guest decoder cases check the context/rate combinations,
seeded decoders, both reversible transforms, all hybrid distance settings,
overlapping copies, non-word tails, RAM-end boundaries, zeroed scratch and reset
registers. Standard range-model bitstreams are cross-checked against the
existing encoder. Every fitting per-family winner is additionally extracted
on canonical WASM and compared byte-for-byte with its frozen linked image.

Runtime comparisons are recorded separately in `runtime-summary.json`: every
RGBA frame and PCM block is compared with the baseline for the requested frame
count. **All eight winners passed 120 frames (2 seconds) in this run**, including
nonblack rendered output and nonzero audio for the seven audible demos; Koi is
silent. A test-only guest delay aligns absolute clocks after extraction, restores
the RAM entry instruction, and verifies RAM and register state before either
application resumes. The fixture reuses dead decoder ROM and is never written
to the delivered cartridges. This avoids treating a startup-time difference as
a visual or audio regression. This is not a full-sequence artistic review,
browser playback test or deployment check.

Evidence paths under `artifacts/pack/research/`:

- `summary.json`: all family winners, sizes and extraction checks.
- `<name>/scan.json`: all candidates, source/image/cartridge hashes, baseline
  report, parameters and measured extraction costs.
- `<name>/<family>.db32` and `.packed.asm`: self-contained fitting candidates.
- `<name>/baseline.db32`, `baseline.image.bin`, `input.asm`, and
  `original-report.json`: frozen comparison inputs.
- `runtime-summary.json`, `<name>/runtime.json`, and `runtime-*.png`: runtime
  parity evidence and representative frames.
- `winners/`: a collected copy of the eight verified winning `.db32` and
  `.packed.asm` files with a manifest, also bundled as `db32-packing-winners.zip`.

The measured winners are candidates for a future production packer change.
The corpus includes related demos by the same authors, so a broader independent
holdout corpus would be appropriate before choosing new default search settings.
