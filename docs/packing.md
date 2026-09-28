# Self-extracting DB32 cartridges

The offline packer assembles a program at its final RAM addresses, compresses
it, and puts an ordinary DB32 CPU decoder in front of the stream. The resulting
`.db32` boots and extracts itself in the VM. There is no host decompression,
extra input, hidden asset file, or change to the **4096-byte payload limit**.

```sh
npm run build
npm run pack -- examples/ray-tracer.asm -o artifacts/ray-packed.db32
npm run pack -- examples/dynamic-kernel.asm --load 0x2d000 -o artifacts/dynamic-packed.db32
node scripts/validate-demo.mjs artifacts/dynamic-packed.db32 --frames 120 --out artifacts/dynamic-check
```

The packer needs only Node.js 22+ and the bundled WASM engine/linker. Maintainers
run `npm run build` with Rust after engine or assembler changes. The standalone
`demobench-agent-kit` includes both prebuilt modules and exposes the same command
as `npm run compress -- SOURCE.asm -o OUTPUT.db32`. Reports pin both module hashes.

## Whole demos and RAM layout

Use `.profile dynamic-1` for compressed GPU/SPU code. Version 4 adds validated
RAM kernels and permits runtime-generated or rewritten kernels. The previous
three profiles are unchanged. A new-profile cartridge requires the updated
VM and authoring kit. See the [dynamic-1 contract](../spec/dynamic-1.md).

The default image address is `0x2c000`, with temporary scratch at `0x10000`.
Override using `--load` and `--scratch`. The packer checks bounds, image/scratch
overlap, exact extraction, register restoration and that other RAM is zero at
handoff. Scratch is erased before the application runs. It cannot infer all
addresses an arbitrary program computes later: reserve the image in your RAM
map, including space for its padding and any stack, audio or graphics buffers.
For example, ASTRA's audio output and Pelican's scene table require moving the
packed image above them; the benchmark uses `--load 0x2d000`.

The offline assembler resolves code/data labels to their RAM addresses, CPU
relative branches/calls to their actual targets, and GPU absolute branches to
the submitted kernel. Use `li` for absolute addresses; `addi ..., r0, label`
cannot hold a RAM address in its signed 16-bit immediate. A kernel binding is
still a base plus byte offsets. If an old demo binds all of ROM at address zero,
move that binding to the image base and subtract that base from label-based
offsets and lengths. The reproducible ASTRA adaptation is in
[`tools/pack/benchmark.mjs`](../tools/pack/benchmark.mjs).

For existing profiles, CPU code and data can be compressed while kernels stay
in ROM. The optional `.section rom` / `.section ram` directives select those
spans; default is RAM. `.equ` and `.profile` declarations are shared. `.entry`
must select a CPU instruction in RAM. ROM is linked first at address zero,
followed physically by the decoder and stream. All count toward the limit.
GPU/SPU instructions in a RAM section require `dynamic-1`. `.org` and `__p*`
symbols are reserved for the packer. Regular `assemble()` continues to reject
oversize cartridges; only the separate offline image API supports sparse RAM
origins and larger source images.

## Compression search

The default search compares **complete cartridge size**, including the decoder:

- **DBLZ:** overlapping LZ matches, interlaced Elias-gamma lengths, nine distance
  encodings, and dynamic programming to choose a minimum-bit parse over the
  discovered matches. A bounded nearest-first hash chain controls offline work.
  `--chain 1024` explores more candidates than the default 256.
- **Four-byte shuffle + DBLZ:** gathers the byte lanes of instructions to expose
  repeated opcode/register/immediate patterns. It needs a temporary image-sized
  RAM span, an inverse shuffle, and up to three padding bytes. These costs are
  counted; this option is skipped if disjoint scratch will not fit.
- **Adaptive range coding:** one, two or four separate literal trees and four
  adaptation rates, exploiting the regular byte lanes of DB32 instructions.
  Models start implicitly at probability 1/2, need no cartridge table, and use
  512–2048 temporary RAM bytes. It can compress better but extracts more slowly.
- **Stored image:** a smaller copy stub wins when compression overhead is too
  high. It still costs space relative to a directly executable tiny demo.

`--codec auto|dblz|range|store` and `--filter auto|none|shuffle4` constrain the
search. The default tries 31 candidates when scratch permits. It is an optimal
parse within the DBLZ match search, not a claim of a globally optimal compressor.
There is no universal expansion ratio: instruction mix and assets determine
the result. High-entropy input can grow, and the packer rejects the final result
if it exceeds 4096 bytes.

Measured on the included sources (decoder included, 32-byte header excluded):

| Demo | Original | Packed | Space saved | Free payload |
| --- | ---: | ---: | ---: | ---: |
| ASTRA | 4,016 B | 2,471 B | 38.5% | 1,625 B |
| Neon Stadium | 3,604 B | 1,920 B | 46.7% | 2,176 B |
| Pelican | 4,064 B | 2,824 B | 30.5% | 1,272 B |
| CPU ray tracer | 2,072 B | 1,403 B | 32.3% | 2,693 B |
| GPU ray tracer | 1,652 B | 1,285 B | 22.2% | 2,811 B |
| Signal Garden | 1,400 B | 1,095 B | 21.8% | 3,001 B |
| Aurora | 864 B | 802 B | 7.2% | 3,294 B |
| RGB study | 436 B | 544 B | −24.8% | 3,552 B |

ASTRA's relocation adaptation expands the linked image to 4,048 B before
compression; this table compares against the original 4,016-byte cartridge.
ASTRA and Neon Stadium select DBLZ with a 308-byte decoder. Pelican and the CPU
ray tracer select range coding with a 352-byte decoder. Extraction costs are
196,135 / 151,485 / 823,411 / 418,035 ticks respectively, about 16 / 12 / 67 / 34
virtual milliseconds. These are measured startup costs, not host wall times.

## Output and evidence

Each successful command writes the cartridge, a pasteable `.packed.asm`, a JSON
report, the exact linked `.image.bin`, and a source listing. The cartridge is
self-contained; sidecars are inspection evidence. The report records raw image,
ROM, stream and decoder sizes, all candidates, load/scratch ranges, hashes and
measured guest extraction ticks. It runs the selected decoder on canonical WASM
one tick at a time and verifies handoff before the first application instruction.
CPU r1–r14 are zero and r15 is `0x30000`, matching reset. The machine clock and
audio/video clocks advance during extraction; startup delay is real guest work.

```sh
npm test
npm run bench:pack
PACK_BENCH_FRAMES=3600 npm run bench:pack
```

The benchmark compares packed demos against delayed original programs at the
same clock, checking every RGBA frame and PCM block. GPU-only originals use the
new profile for the baseline's silent audio timeline. Results, adapted sources,
cartridges, PNGs and reports go to `artifacts/pack/benchmark/`. Tests separately
cover codec round trips, every DBLZ distance setting on WASM, RAM boundaries,
oversize rejection, >4 KiB source/kernel execution, runtime kernel edits,
profile isolation, malformed kernels and SPU snapshot/fallback behavior.

For local browser acceptance, first run the benchmark to create its fixtures,
then `node tools/pack/prepare-browser.mjs`. With the dev server running, open
`http://127.0.0.1:4173/pack-checks.html`. It exercises hardware bounds/fallback,
same-address RAM code edits, the self-modifying packed example, and packed
ASTRA with GPU and SPU acceleration. These test pages and fixtures are excluded
from deployment assets.

Canonical output parity, browser execution, real-time performance, and deployed
VM availability are separate checks. Nothing in the pack command deploys the VM.
