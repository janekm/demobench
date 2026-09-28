// Capture a cartridge at a full 60 fps using the time-dilated engine build:
// every vblank has 32x the reference tick budget, so each frame's GPU work
// completes before presentation (what the WebGPU path does in the browser).
// usage: node .capture-engine/smooth-capture.mjs demo.asm --frames 3600 --out cap/<demo>  (see build-capture-engine.sh)
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { createMachine } from './wasm-host.mjs';

const args = process.argv.slice(2);
const src = args[0];
const opt = { frames: 600, out: 'out' };
for (let i = 1; i < args.length; i++) {
  if (args[i] === '--frames') opt.frames = +args[++i];
  else if (args[i] === '--out') opt.out = args[++i];
}
mkdirSync(opt.out, { recursive: true });
const m = createMachine();
const text = readFileSync(src, 'utf8');
const cart = src.endsWith('.db32') ? readFileSync(src) : m.assemble(text);
m.load(cart);
const e = m.exports;

const ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgba', '-s', '160x120', '-r', '60', '-i', '-',
  '-c:v', 'ffv1', '-pix_fmt', 'bgr0', join(opt.out, 'raw160.mkv')], { stdio: ['pipe', 'inherit', 'inherit'] });

const chunks = [];
let prev = null, changed = 0;
const t0 = performance.now();
for (let f = 1; f <= opt.frames; f++) {
  m.runFrames(1);
  chunks.push(m.audio());
  const rgba = m.frame();
  const h = createHash('md5').update(rgba).digest('hex');
  if (h !== prev) changed++;
  prev = h;
  if (!ff.stdin.write(Buffer.from(rgba))) await new Promise(r => ff.stdin.once('drain', r));
  if (f % 300 === 0) process.stderr.write(`${src} frame ${f} changed ${changed} ${((performance.now() - t0) / 1000).toFixed(0)}s\n`);
}
ff.stdin.end();
await new Promise(r => ff.on('close', r));

let total = 0; for (const c of chunks) total += c.length;
const bytes = Buffer.alloc(44 + total * 2);
bytes.write('RIFF', 0); bytes.writeUInt32LE(bytes.length - 8, 4); bytes.write('WAVEfmt ', 8);
bytes.writeUInt32LE(16, 16); bytes.writeUInt16LE(1, 20); bytes.writeUInt16LE(2, 22);
bytes.writeUInt32LE(48000, 24); bytes.writeUInt32LE(192000, 28); bytes.writeUInt16LE(4, 32); bytes.writeUInt16LE(16, 34);
bytes.write('data', 36); bytes.writeUInt32LE(total * 2, 40);
let o = 44;
for (const c of chunks) for (const v of c) { bytes.writeInt16LE(Math.max(-32768, Math.min(32767, Math.round(v * 32767))), o); o += 2; }
writeFileSync(join(opt.out, 'audio.wav'), bytes);
const info = m.info();
writeFileSync(join(opt.out, 'stats.json'), JSON.stringify({ frames: opt.frames, changed, wallS: (performance.now() - t0) / 1000,
  overruns: info.audio.overruns, peak: info.audio.peak, dispatches: info.gpu.dispatches, payload: info.payloadBytes }, null, 1));
console.log(`${src}: ${opt.frames} frames, ${changed} changed, ${info.gpu.dispatches} dispatches, overruns ${info.audio.overruns}`);
