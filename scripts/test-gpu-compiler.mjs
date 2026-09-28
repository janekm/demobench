import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createMachine } from './wasm-host.mjs';
import { compileKernel } from '../web/gpu-compiler.js';

const tests = [];
const test = (name, run) => tests.push([name, run]);
const word = (op, d = 0, a = 0, b = 0, c = 0) =>
  (op | d << 8 | a << 13 | b << 18 | c << 23) >>> 0;
const payload = words => {
  const bytes = new Uint8Array(words.length * 4);
  const view = new DataView(bytes.buffer);
  words.forEach((value, index) => view.setUint32(index * 4, value >>> 0, true));
  return bytes;
};
const descriptors = [
  { base: 0, len: 4096, flags: 1 },
  { base: 0x10000, len: 57600, flags: 3 },
  { base: 0, len: 0, flags: 0 },
  { base: 0, len: 0, flags: 0 },
];
function compile(words, bindings = descriptors, allowReadWrite = false) {
  const rom = payload(words);
  // A RO ROM binding cannot extend beyond a synthetic test kernel.
  const local = bindings.map(b => b.flags === 1 && b.base === 0 ? { ...b, len: rom.length } : b);
  return compileKernel({ rom, codeBase: 0, codeLength: rom.length, bindings: local,
    width: 2, height: 1, allowReadWrite });
}

test('every opcode compiles from the binary ISA with validated fields', () => {
  const words = [];
  const branches = [];
  for (let op = 0; op <= 42; op++) {
    let d = 1, a = 0, b = 0, c = 0;
    if (op === 0 || op === 42) d = 0;
    if (op === 34) c = 0;
    if (op === 35 || op === 37) b = 0;
    if (op === 36 || op === 38 || op === 39) b = 1;
    if (op === 40 || op === 41) a = b = c = 0;
    words.push(word(op, d, a, b, c));
    if ([1, 40, 41, 42].includes(op)) {
      if (op >= 40) branches.push(words.length);
      words.push(op === 1 ? 0x3f800000 : 0);
    }
  }
  const end = 0;
  for (const literalIndex of branches) words[literalIndex] = end;
  const result = compile(words);
  assert.equal(result.instructionCount, 43);
  assert.ok(result.blockCount < 10, `expected fusion, got ${result.blockCount} blocks`);
  assert.equal(result.entryPoint, 'main');
  assert.equal(result.workgroupSize, 64);
  assert.deepEqual(result.writableBindings, [{ index: 1, base: 0x10000, len: 57600 }]);
  assert.equal((result.code.match(/case \d+u:/g) || []).length, result.blockCount);
  for (const token of ['@workgroup_size(64)', 'atomicCompareExchangeWeak', 'reflect(', 'inverseSqrt(', 'let disc =', 'status: array<atomic<u32>>']) {
    assert.ok(result.code.includes(token), token);
  }
});

test('branches must point to instruction starts within the submitted ROM range', () => {
  assert.throws(() => compile([word(42), 4, word(0)]), /branch.*instruction start/);
  assert.throws(() => compile([word(42), 100, word(0)]), /branch.*instruction start/);
  const rom = payload([word(0), word(42), 0]);
  const binding = [{ base: 0, len: rom.length, flags: 1 }, ...descriptors.slice(1)];
  assert.throws(() => compileKernel({ rom, codeBase: 4, codeLength: 8, bindings: binding, width: 1, height: 1 }), /branch.*instruction start/);
  assert.throws(() => compileKernel({ rom, codeBase: 0, codeLength: 10, bindings: binding, width: 1, height: 1 }), /complete aligned/);
});

test('reserved bits, operands and static binding hazards fall back cleanly', () => {
  assert.throws(() => compile([0x10000000]), /reserved bits/);
  assert.throws(() => compile([word(3, 1, 6)]), /built-in/);
  assert.throws(() => compile([word(28, 0, 0, 0)]), /vector destination/);
  assert.throws(() => compile([word(31, 31, 30, 0)]), /vector source/);
  assert.throws(() => compile([word(34, 1, 0, 0, 29)]), /sphere center/);
  assert.throws(() => compile([word(39, 30, 0, 1)]), /RGB vector source/);
  assert.throws(() => compile([word(35, 1, 0, 1)]), /writable.*fallback/);
  assert.throws(() => compile([word(37, 1, 0, 1)]), /writable.*fallback/);
  assert.throws(() => compile([word(36, 1, 0, 0)]), /read-only.*fallback/);
  assert.throws(() => compileKernel({ rom: payload([word(0)]), codeBase: 0, codeLength: 4,
    bindings: [{ base: 0, len: 8, flags: 1 }, ...descriptors.slice(1)], width: 1, height: 1 }), /ROM\/RAM/);
  assert.throws(() => compileKernel({ rom: payload([word(0)]), codeBase: 0, codeLength: 4,
    bindings: [{ base: 0, len: 4, flags: 1 }, { base: 0x2ffff, len: 2, flags: 3 },
      ...descriptors.slice(2)], width: 1, height: 1 }), /exceeds guest mirror/);
});

test('SPU read/write loads use atomic output while read-only loads keep input', () => {
  const result = compile([
    word(35, 1, 0, 1),
    word(37, 2, 0, 1),
    word(35, 3, 0, 0),
    word(37, 4, 0, 0),
    word(0),
  ], descriptors, true);
  assert.ok(result.code.includes('r[1u] = atomicLoad(&outputWords[address >> 2u])'));
  assert.ok(result.code.includes('r[2u] = loadOutputByte(address)'));
  assert.ok(result.code.includes('r[3u] = inputWords[address >> 2u]'));
  assert.ok(result.code.includes('r[4u] = loadByte(address)'));
  assert.deepEqual(result.writableBindings, [{ index: 1, base: 0x10000, len: 57600 }]);
});

test('scalar discard and high scalar destinations coexist with RGB vector g0', () => {
  const result = compile([
    word(31, 0, 0, 0),
    word(31, 30, 0, 0),
    word(31, 31, 0, 0),
    word(39, 0, 0, 1),
    word(0),
  ]);
  assert.equal(result.instructionCount, 5);
  assert.ok(result.code.includes('storeByte(address + 2u'));
});

test('the shipped ray tracer compiles from its assembled cartridge', () => {
  const source = readFileSync(new URL('../examples/gpu-ray-tracer.asm', import.meta.url), 'utf8');
  const machine = createMachine();
  const cart = machine.assemble(source);
  const rom = cart.slice(32);
  const listing = new TextDecoder().decode(new Uint8Array(machine.exports.memory.buffer,
    machine.exports.db_listing_ptr(), machine.exports.db_listing_len()));
  const gpuLines = listing.split('\n').filter(line => /\s+g\.[a-z]/.test(line));
  assert.ok(gpuLines.length > 200, 'example has a substantial guest kernel');
  const address = line => parseInt(line.match(/^([0-9a-f]+)/)?.[1], 16);
  const codeBase = address(gpuLines[0]);
  const codeLength = address(gpuLines.at(-1)) + 4 - codeBase;
  const sceneLine = listing.split('\n').find(line => /\s+\.float\s/.test(line));
  const sceneBase = address(sceneLine);
  const result = compileKernel({ rom, codeBase, codeLength, width: 80, height: 60,
    bindings: [
      { base: 0x10000, len: 57600, flags: 3 },
      { base: sceneBase, len: 84, flags: 1 },
      { base: 0, len: 0, flags: 0 },
      { base: 0, len: 0, flags: 0 },
    ] });
  assert.equal(result.instructionCount, gpuLines.length);
  assert.ok(result.blockCount < result.instructionCount / 2,
    `${result.blockCount} blocks for ${result.instructionCount} instructions`);
  console.log(`  ray kernel: ${result.instructionCount} instructions in ${result.blockCount} blocks`);
  assert.ok(result.code.includes(`case ${codeBase}u:`));
  assert.deepEqual(result.writableBindings, [{ index: 0, base: 0x10000, len: 57600 }]);
});

test('dynamic RAM code compiles with absolute branches and content changes', () => {
  const ram = new Uint8Array(131072), base = 0x2c000;
  const code = payload([word(1, 1), 7, word(42), base + 16, word(0)]);
  ram.set(code, base - 0x10000);
  const descriptor = { rom: payload([32]), ram, codeBase: base, codeLength: code.length,
    width: 1, height: 1, bindings: Array.from({ length: 4 }, () => ({ base: 0, len: 0, flags: 0 })) };
  assert.throws(() => compileKernel(descriptor), /ROM range/);
  const a = compileKernel({ ...descriptor, allowRamCode: true });
  assert.ok(a.code.includes('r[1u] = 7u'));
  new DataView(ram.buffer).setUint32(base - 0x10000 + 4, 9, true);
  const b = compileKernel({ ...descriptor, allowRamCode: true });
  assert.ok(b.code.includes('r[1u] = 9u'));
  assert.notEqual(a.code, b.code);
  assert.throws(() => compileKernel({ ...descriptor, allowRamCode: true, codeBase: 0x2fffc }), /ROM range/);
  assert.throws(() => compileKernel({ ...descriptor, allowRamCode: true, codeLength: 65540 }), /aligned/);
  assert.throws(() => compileKernel({ ...descriptor, allowRamCode: true,
    bindings: [{ base: 0x8000, len: 4, flags: 1 }, ...descriptor.bindings.slice(1)] }), /ROM\/RAM/);
});

let passed = 0;
for (const [name, run] of tests) {
  try { run(); passed++; console.log(`ok - ${name}`); }
  catch (error) { console.error(`not ok - ${name}`); throw error; }
}
console.log(`${passed} GPU compiler tests passed`);
