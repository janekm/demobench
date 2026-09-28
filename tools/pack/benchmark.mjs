import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { packSource, writePacked } from './pack.mjs';
import { createMachine, FRAME_TICKS } from '../../scripts/wasm-host.mjs';
import { png } from '../../scripts/png.mjs';

const out = process.env.PACK_BENCH_OUT ?? 'artifacts/pack/benchmark'; mkdirSync(out, { recursive: true });
const frames = Number(process.env.PACK_BENCH_FRAMES ?? 120);
assert.ok(Number.isInteger(frames) && frames >= 1 && frames <= 3600);
const demos = ['rgb-study', 'aurora', 'ray-tracer', 'gpu-ray-tracer', 'signal-garden', 'neon-stadium', 'astra', 'pelican'];
const selected = process.env.PACK_BENCH_DEMOS?.split(',') ?? demos;
assert.ok(selected.length && selected.every(name => demos.includes(name)));
const records = [];
writeFileSync(`${out}/summary.json`, '[]\n');
for (const name of selected) {
  const original = readFileSync(`examples/${name}.asm`, 'utf8');
  const originalMachine = createMachine(), originalCart = originalMachine.assemble(original);
  const dynamic = /\.profile (gpu|spu)-1/.test(original);
  let source = original.replace(/\.profile (gpu|spu)-1/, '.profile dynamic-1');
  const load = 0x2d000;
  // ASTRA binds its whole old ROM at byte zero, and uses absolute addresses as
  // binding offsets. Move that binding and express offsets relative to IMAGE.
  if (name === 'astra') {
    source = `.equ IMAGE, ${load}\n` + source
      .replace(/addi (r\d+), r0, (visual|music|rom_end)(\s*\n)/g, 'li $1, $2$3')
      .replace(/sw r0, 80\(r10\)/, 'li r1, IMAGE\n    sw r1, 80(r10)')
      .replace(/sw r0, 272\(r12\)/, 'li r1, IMAGE\n    sw r1, 272(r12)')
      .replace(/li r1, rom_end/g, 'li r1, rom_end-IMAGE')
      .replace(/g\.li (g\d+), (logo|roots|notes)\b/g, 'g.li $1, $2-IMAGE');
  }
  writeFileSync(`${out}/${name}.input.asm`, source);
  const result = packSource(source, { load }); writePacked(result, `${out}/${name}.db32`);
  const r = result.report;
  r.originalPayloadBytes = originalCart.length - 32;
  r.savedAgainstOriginal = r.originalPayloadBytes - r.payloadBytes;
  // Delay the original ROM program to the extraction handoff clock. This is a
  // baseline fixture, not a host shortcut in the delivered compressed cartridge.
  const ticks = r.verification.extractionTicks;
  const entry = original.match(/^\s*\.entry\s+(\w+)/m)?.[1];
  assert.ok(entry);
  const count = Math.floor((ticks - 3) / 2), padding = (ticks - 3) % 2;
  const delay = `.entry __baseline\n__baseline:\nli r1, ${count}\n__wait:\naddi r1,r1,-1\nbne r1,r0,__wait\n${'nop\n'.repeat(padding)}j ${entry}\n`;
  const baseline = createMachine();
  baseline.load(baseline.assemble(delay + original.replace(/^\s*\.entry\s+\w+/m, '').replace('.profile gpu-1', '.profile dynamic-1')));
  for (let left = ticks; left > 0;) { const n = Math.min(left, FRAME_TICKS); baseline.run(n); left -= n; baseline.audio(); }
  result.machine.audio();
  const pcm = createHash('sha256');
  let peak = 0, maxGpuTicks = 0, maxSpuTicks = 0;
  const runFrames = name === 'ray-tracer' ? Math.max(480, frames) : frames;
  for (let frame = 0; frame < runFrames; frame++) {
    baseline.runFrames(1); result.machine.runFrames(1);
    const a = baseline.audio(), b = result.machine.audio();
    assert.ok(Buffer.from(b.buffer).equals(Buffer.from(a.buffer)), `${name}: exact PCM at frame ${frame}`);
    assert.ok(Buffer.from(result.machine.frame()).equals(Buffer.from(baseline.frame())), `${name}: exact RGBA at frame ${frame}`);
    pcm.update(Buffer.from(b.buffer, b.byteOffset, b.byteLength));
    for (const sample of b) peak = Math.max(peak, Math.abs(sample));
    maxGpuTicks = Math.max(maxGpuTicks, result.machine.exports.db_gpu_last_ticks());
    maxSpuTicks = Math.max(maxSpuTicks, result.machine.exports.db_spu_last_ticks());
  }
  writeFileSync(`${out}/${name}.png`, png(160, 120, result.machine.frame()));
  r.runtime = { frames: runFrames, exactRgbaAgainstDelayedOriginal: true, exactPcmAgainstDelayedOriginal: true,
    pcmSha256: pcm.digest('hex'), peak, maxGpuTicks, maxSpuTicks, final: result.machine.info() };
  writeFileSync(`${out}/${name}.json`, JSON.stringify(r, null, 2) + '\n');
  records.push({ name, profile: dynamic ? 'dynamic-1' : 'bootstrap-1', original: r.originalPayloadBytes,
    linked: r.sourceBytes, packed: r.payloadBytes, saved: r.savedAgainstOriginal, codec: r.codec,
    filter: r.filter, decoder: r.decoderBytes, ticks, frames: runFrames, parity: true });
  writeFileSync(`${out}/summary.json`, JSON.stringify(records, null, 2) + '\n');
  console.log(`${name}: ${r.originalPayloadBytes} -> ${r.payloadBytes}, ${runFrames} frames exact RGBA/PCM`);
}
