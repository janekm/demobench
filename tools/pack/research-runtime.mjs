import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { createLinker } from './linker.mjs';
import { linkSource } from './pack.mjs';
import { verifyExtraction, sha } from './research.mjs';
import { FRAME_TICKS } from '../../scripts/wasm-host.mjs';
import { png } from '../../scripts/png.mjs';

const out = process.argv[2] ?? 'artifacts/pack/research';
const frames = Number(process.env.PACK_RESEARCH_FRAMES ?? 120);
assert.ok(Number.isInteger(frames) && frames >= 1 && frames <= 3600);
const summary = JSON.parse(readFileSync(`${out}/summary.json`)), linker = createLinker();
const results = [];
const json = (file, value) => writeFileSync(file, JSON.stringify(value, null, 2) + '\n');

// Test fixture only: after verified extraction, reuse dead decoder ROM for a
// guest delay. A temporary jump at the RAM entry routes through this trampoline,
// which restores the original entry word and reset registers before handoff.
// This aligns absolute clocks without adding bytes to delivered cartridges.
// No fixture patches or host decompression appear in the runnable artifacts.
function alignClock(machine, image, target) {
  const now = machine.info().ticks, remaining = target - now;
  assert.ok(remaining >= 13);
  const count = Math.floor((remaining - 11) / 2), pad = (remaining - 11) % 2;
  const original = image.data.readUInt32LE(image.entry - image.load);
  const delay = linker.link(`li r1, ${image.entry}\nli r2, ${original}\nsw r2, 0(r1)\nli r1, ${count}\nwait:\naddi r1,r1,-1\nbne r1,r0,wait\n${'nop\n'.repeat(pad)}mov r2,r0\nj ${image.entry}\n`).bytes;
  const jump = linker.link(`.org ${image.entry}\n.entry jump\njump: j 0`).bytes.slice(image.entry);
  new Uint8Array(machine.exports.memory.buffer, machine.exports.db_rom_ptr(), machine.exports.db_rom_len()).set(delay);
  new Uint8Array(machine.exports.memory.buffer, machine.exports.db_ram_ptr(), 131072).set(jump, image.entry - 0x10000);
  let steps = 0;
  do { machine.run(1); steps++; if (steps % FRAME_TICKS === 0) machine.audio(); }
  while (machine.exports.db_pc() !== image.entry && steps <= remaining);
  assert.equal(machine.info().ticks, target, 'Fixture aligns exact absolute guest ticks');
  const ram = new Uint8Array(machine.exports.memory.buffer, machine.exports.db_ram_ptr(), 131072);
  assert.deepEqual(Buffer.from(ram.slice(image.load - 0x10000, image.load - 0x10000 + image.data.length)), image.data);
  assert.ok(!ram.slice(0, image.load - 0x10000).some(x => x));
  assert.ok(!ram.slice(image.load - 0x10000 + image.data.length).some(x => x));
  for (let r = 1; r < 16; r++) assert.equal(machine.exports.db_register(r) >>> 0, r === 15 ? 0x30000 : 0);
  machine.audio();
}

for (const item of summary) {
  const dir = `${out}/${item.name}`, scan = JSON.parse(readFileSync(`${dir}/scan.json`)), best = item.bests[0];
  const source = readFileSync(`${dir}/input.asm`, 'utf8'), image = linkSource(source, scan.load);
  assert.equal(sha(image.data), scan.imageSha256);
  const baselineCart = readFileSync(`${dir}/baseline.db32`), bestCart = readFileSync(`${dir}/${best.family}.db32`);
  assert.equal(sha(baselineCart), scan.baseline.cartridgeSha256);
  assert.equal(sha(bestCart), best.cartridgeSha256);
  const baseline = verifyExtraction(baselineCart, image).machine, candidate = verifyExtraction(bestCart, image).machine;
  const target = (Math.ceil(Math.max(baseline.info().ticks, candidate.info().ticks) / FRAME_TICKS) + 1) * FRAME_TICKS;
  alignClock(baseline, image, target); alignClock(candidate, image, target);
  const rgbaHash = createHash('sha256'), pcmHash = createHash('sha256');
  let nonBlackFrames = 0, nonzeroAudioSamples = 0, peak = 0;
  for (let frame = 0; frame < frames; frame++) {
    baseline.runFrames(1); candidate.runFrames(1);
    const expectedFrame = baseline.frame(), actualFrame = candidate.frame(), expectedAudio = baseline.audio(), actualAudio = candidate.audio();
    assert.deepEqual(actualFrame, expectedFrame, `${item.name}: frame ${frame} RGBA`);
    assert.deepEqual(actualAudio, expectedAudio, `${item.name}: frame ${frame} PCM`);
    rgbaHash.update(actualFrame); pcmHash.update(Buffer.from(actualAudio.buffer, actualAudio.byteOffset, actualAudio.byteLength));
    if (actualFrame.some((v, i) => i % 4 !== 3 && v !== 0)) nonBlackFrames++;
    for (const x of actualAudio) { assert.ok(Number.isFinite(x)); if (x !== 0) nonzeroAudioSamples++; peak = Math.max(peak, Math.abs(x)); }
    if ([0, 29, 59, frames - 1].includes(frame)) writeFileSync(`${dir}/runtime-${String(frame + 1).padStart(4, '0')}.png`, png(160, 120, actualFrame));
  }
  assert.ok(nonBlackFrames > 0, `${item.name}: rendered actual output`);
  assert.equal(candidate.info().audio.overruns, 0);
  const result = { name: item.name, candidate: best.family, baselineBytes: baselineCart.length - 32, packedBytes: bestCart.length - 32,
    frames, seconds: frames / 60, alignedStartTick: target, exactRgba: true, exactPcm: true, nonBlackFrames, nonzeroAudioSamples,
    peak, rgbaSha256: rgbaHash.digest('hex'), pcmSha256: pcmHash.digest('hex'), candidateSha256: sha(bestCart),
    baselineSha256: sha(baselineCart), imageSha256: sha(image.data), final: candidate.info() };
  json(`${dir}/runtime.json`, result); results.push(result); json(`${out}/runtime-summary.json`, results);
  console.log(`${item.name}: ${frames} frames exact RGBA/PCM; ${nonBlackFrames} visible frames; ${nonzeroAudioSamples} nonzero audio samples`);
}
