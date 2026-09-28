import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { createHash } from 'node:crypto';
import { createMachine, WIDTH, HEIGHT } from './wasm-host.mjs';
import { png } from './png.mjs';

const args = process.argv.slice(2);
const option = (name, fallback) => args.includes(name) ? args[args.indexOf(name) + 1] : fallback;
const frames = Number(option('--frames', '480'));
if (!Number.isInteger(frames) || frames < 1 || frames > 3600) throw new Error('--frames must be 1..3600');
const demo = option('--demo', 'signal-garden');
const source = option('--source', `examples/${demo}.asm`);
const out = resolve(option('--out', `artifacts/${demo}.wav`));
if (!out.endsWith('.wav')) throw new Error('--out must end with .wav');
const machine = createMachine();
const cartridge = machine.assemble(readFileSync(source, 'utf8'));
machine.load(cartridge);
if (machine.info().profileCode < 3) throw new Error('Audio capture requires a spu-1 or dynamic-1 cartridge.');
const chunks = [];
let count = 0, peak = 0, sum = 0, dcSum = 0, clippedSamples = 0, stereoDifference = 0;
const start = performance.now();
for (let frame = 0; frame < frames; frame++) {
  machine.runFrames(1);
  const chunk = machine.audio();
  for (let i = 0; i < chunk.length; i++) {
    if (!Number.isFinite(chunk[i])) throw new Error('Nonfinite PCM');
    peak = Math.max(peak, Math.abs(chunk[i]));
    sum += chunk[i] ** 2;
    dcSum += chunk[i];
    if (Math.abs(chunk[i]) >= 1) clippedSamples++;
    if (!(i & 1)) stereoDifference += Math.abs(chunk[i] - chunk[i + 1]);
  }
  count += chunk.length;
  chunks.push(chunk);
}
const wallMs = performance.now() - start;
const pcm = new Float32Array(count);
let offset = 0;
for (const chunk of chunks) { pcm.set(chunk, offset); offset += chunk.length; }
const bytes = Buffer.alloc(44 + count * 2);
bytes.write('RIFF', 0); bytes.writeUInt32LE(bytes.length - 8, 4); bytes.write('WAVEfmt ', 8);
bytes.writeUInt32LE(16, 16); bytes.writeUInt16LE(1, 20); bytes.writeUInt16LE(2, 22);
bytes.writeUInt32LE(48000, 24); bytes.writeUInt32LE(192000, 28); bytes.writeUInt16LE(4, 32); bytes.writeUInt16LE(16, 34);
bytes.write('data', 36); bytes.writeUInt32LE(count * 2, 40);
for (let i = 0; i < count; i++) bytes.writeInt16LE(Math.max(-32768, Math.min(32767, Math.round(pcm[i] * 32768))), 44 + i * 2);
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, bytes);
writeFileSync(out.slice(0, -4) + '.png', png(WIDTH, HEIGHT, machine.frame()));
const report = { ...machine.info(), source, host:process.version, sampleFrames:count/2, seconds:count/96000, wallMs,
  peak, rms:Math.sqrt(sum / Math.max(count, 1)), dcOffset:dcSum / Math.max(count, 1), clippedSamples,
  meanStereoDifference:stereoDifference / Math.max(count/2, 1),
  pcmFloat32Sha256:createHash('sha256').update(new Uint8Array(pcm.buffer)).digest('hex'),
  wavSha256:createHash('sha256').update(bytes).digest('hex'), output:out };
writeFileSync(out.slice(0, -4) + '.json', JSON.stringify(report, null, 2) + '\n');
writeFileSync(out.slice(0, -4) + '.db32', cartridge);
console.log(JSON.stringify(report, null, 2));
