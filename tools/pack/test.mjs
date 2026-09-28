import assert from 'node:assert/strict';
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { compressCandidates, decompress, shuffle4, unshuffle4 } from './codec.mjs';
import { rangeEncode, rangeDecode } from './range.mjs';
import { decoder } from './stub.mjs';
import { packSource, writePacked } from './pack.mjs';
import { createMachine } from '../../scripts/wasm-host.mjs';

let seed = 0xdbc032;
const random = () => { seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5; return seed >>> 0; };
let cases = 0;
for (const length of [1, 2, 3, 4, 7, 16, 31, 256, 1023, 4096]) {
  for (const pattern of ['random', 'zeros', 'period', 'instructions']) {
    const input = Uint8Array.from({ length }, (_, i) => pattern === 'random' ? random() & 255 :
      pattern === 'zeros' ? 0 : pattern === 'period' ? i % 7 : i % 4 === 3 ? 0 : random() % 16);
    for (const c of compressCandidates(input)) { assert.deepEqual(decompress(c.bytes, length, c.k), input); cases++; }
    for (const lanes of [1, 2, 4]) for (const rate of [3, 4, 5, 6]) {
      const c = rangeEncode(input, { lanes, rate }); assert.deepEqual(rangeDecode(c.bytes, length, c), input); cases++;
    }
    assert.deepEqual(unshuffle4(shuffle4(input)).slice(0, length), input);
  }
}
assert.throws(() => decompress(new Uint8Array(), 20, 0), /Truncated/);
assert.throws(() => decompress(new Uint8Array([1]), 20, 0), /Invalid/);
assert.throws(() => rangeDecode(new Uint8Array(4), 10), /Truncated/);
assert.throws(() => rangeDecode(new Uint8Array(4), NaN), /Invalid/);
console.log(`ok - ${cases} deterministic codec round trips and malformed streams`);

// Exercise every distance parameter in the actual CPU, including overlap and
// a stream ending exactly at the last RAM byte. HALT is the expanded entry.
const input = Uint8Array.from({ length: 1028 }, (_, i) => i < 4 ? (i === 0 ? 32 : 0) : i % 71 < 55 ? i % 7 : random() & 255);
for (const c of compressCandidates(input)) {
  const load = 0x2fbfc; // Image ends exactly at RAM_END.
  const m = createMachine();
  const stub = decoder({ k: c.k, load, length: input.length, entry: load });
  const cart = m.assemble(`${stub}\n.byte ${[...c.bytes]}\n__p_data_end:`);
  m.load(cart);
  for (let ticks = 0; m.exports.db_pc() !== load && ticks < 2000000; ticks++) m.run(1);
  assert.equal(m.exports.db_pc(), load);
  const ram = new Uint8Array(m.exports.memory.buffer, m.exports.db_ram_ptr(), 131072);
  assert.deepEqual(ram.slice(load - 0x10000, load - 0x10000 + input.length), input);
}
console.log('ok - all nine DBLZ distance settings decode on the WASM CPU');

for (const [codec, filter] of [['store', 'none'], ['dblz', 'none'], ['dblz', 'shuffle4'], ['range', 'none']]) {
  const result = packSource('halt\n' + '.word 0x1234abcd, 0, 0, 0\n'.repeat(120), { codec, filter });
  assert.ok(result.report.verification.exactRamImage);
  result.machine.run(1); assert.equal(result.machine.info().status, 2);
}
assert.throws(() => packSource('.profile gpu-1\nhalt\ng.end'), /dynamic-1/);
assert.throws(() => packSource('halt', { load: 0x10001 }), /aligned/);
assert.throws(() => packSource('halt', { filter: 'shuffle4', scratch: 0x2c000 }), /disjoint/);
assert.throws(() => packSource('halt', { codec: 'range', filter: 'shuffle4' }), /requires/);
assert.throws(() => packSource('halt\n' + '.word 1\n'.repeat(1100), { codec: 'store' }), /over the 4096/);
console.log('ok - decoder modes restore registers and clear scratch; limits reject invalid images');

const legacy = packSource(`.profile gpu-1
.entry boot
.section rom
kernel: g.li g1,17
g.st g1,g0,0
g.end
kernel_end:
.section ram
boot: li r10,0xf3000
li r1,kernel
sw r1,0(r10)
li r1,kernel_end-kernel
sw r1,4(r10)
addi r1,r0,1
sw r1,8(r10)
sw r1,12(r10)
li r1,0x10000
sw r1,64(r10)
addi r1,r0,4
sw r1,68(r10)
addi r1,r0,3
sw r1,72(r10)
addi r1,r0,1
sw r1,16(r10)
halt
`);
legacy.machine.runFrames(1);
assert.equal(legacy.machine.info().profile, 'gpu-1');
assert.equal(legacy.machine.info().gpu.dispatches, 1);
assert.equal(new Uint8Array(legacy.machine.exports.memory.buffer, legacy.machine.exports.db_ram_ptr(), 1)[0], 17);
console.log('ok - legacy GPU profile links ROM kernels with compressed RAM CPU code');

// This 8 KiB source contains a >4 KiB RAM kernel and an SPU kernel. The first
// dispatch writes 17, then the CPU rewrites the literal and dispatches 29.
const large = `.profile dynamic-1
.entry start
start:
li r10,0xf3000
li r1,kernel
sw r1,0(r10)
li r1,kernel_end-kernel
sw r1,4(r10)
addi r1,r0,1
sw r1,8(r10)
sw r1,12(r10)
li r1,0x10000
sw r1,64(r10)
addi r1,r0,4
sw r1,68(r10)
addi r1,r0,3
sw r1,72(r10)
addi r1,r0,1
sw r1,16(r10)
wait1: lw r2,20(r10)
beq r1,r2,wait1
li r3,kernel+4
addi r2,r0,29
sw r2,0(r3)
sw r1,16(r10)
wait2: lw r2,20(r10)
beq r1,r2,wait2
li r10,0xf6000
li r1,sound
sw r1,64(r10)
li r1,sound_end-sound
sw r1,68(r10)
addi r1,r0,1
sw r1,72(r10)
sw r1,76(r10)
li r1,0x11000
sw r1,80(r10)
sw r1,256(r10)
li r1,2048
sw r1,260(r10)
addi r1,r0,3
sw r1,264(r10)
addi r1,r0,1
sw r1,0(r10)
halt
kernel: g.li g1,17
${'g.add g1,g1,g0\n'.repeat(1100)}
g.st g1,g0,0
g.end
kernel_end:
sound: g.fli g1,0.25
g.st g1,g0,0
g.end
sound_end:
.word ${Array.from({ length: 900 }, (_, i) => i % 16).join(',')}
`;
const result = packSource(large);
assert.ok(result.report.sourceBytes > 8000);
assert.ok(result.report.payloadBytes < 4096);
result.machine.audio(); result.machine.runFrames(3);
const ram = new Uint8Array(result.machine.exports.memory.buffer, result.machine.exports.db_ram_ptr(), 131072);
assert.equal(new DataView(ram.buffer, ram.byteOffset).getUint32(0, true), 29);
assert.equal(result.machine.info().gpu.dispatches, 2);
assert.ok(result.machine.audio().some(n => n === 0.25));
assert.equal(result.machine.info().audio.overruns, 0);
mkdirSync('artifacts/pack', { recursive: true });
writeFileSync('artifacts/pack/large-dynamic.input.asm', large);
writePacked(result, 'artifacts/pack/large-dynamic.db32');
console.log(`ok - ${result.report.sourceBytes}-byte linked image -> ${result.report.payloadBytes}-byte cartridge; RAM GPU edits and audio execute`);

// Actual CPU-rendered output retains the original image after relocation.
const source = readFileSync('examples/rgb-study.asm', 'utf8');
const original = createMachine(); original.load(original.assemble(source)); original.runFrames(120);
const packed = packSource(source); packed.machine.runFrames(120);
assert.deepEqual(packed.machine.frame(), original.frame());
console.log('ok - original and self-extracted RGB demo render identically');
