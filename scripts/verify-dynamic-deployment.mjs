import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';

const origin = 'https://demobench.janekm.com';
const hash = data => createHash('sha256').update(data).digest('hex');
const files = ['build.json', 'machine.wasm', 'machine-worker.js', 'gpu-compiler.js', 'gpu-webgpu.js',
  'app.js', 'audio-player.js', 'audio-worklet.js', 'index.html'];
const checks = [];
let wasm;
for (const name of files) {
  const response = await fetch(`${origin}/${name}`, { cache: 'no-store', signal: AbortSignal.timeout(30000) });
  assert.equal(response.status, 200, name);
  const bytes = Buffer.from(await response.arrayBuffer());
  assert.equal(hash(bytes), hash(readFileSync(`web/${name}`)), `${name}: live asset differs from tested file`);
  checks.push({ path: name, status: response.status, bytes: bytes.length, sha256: hash(bytes) });
  if (name === 'machine.wasm') wasm = bytes;
}
const module = new WebAssembly.Module(wasm);
assert.deepEqual(WebAssembly.Module.imports(module), []);
const runs = [];
for (const name of ['astra', 'neon-stadium', 'pelican']) {
  const e = new WebAssembly.Instance(module, {}).exports;
  const cart = readFileSync(`artifacts/pack/benchmark/${name}.db32`);
  const ptr = e.db_input_ptr();
  new Uint8Array(e.memory.buffer, ptr, cart.length).set(cart);
  assert.equal(e.db_load(cart.length), 0, name);
  assert.equal(e.db_profile(), 4);
  let peak = 0, sampleFrames = 0;
  const frames = new Set();
  for (let i = 0; i < 120; i++) {
    const status = e.db_run(204800);
    assert.notEqual(status, 3, `${name}: ${new TextDecoder().decode(new Uint8Array(e.memory.buffer, e.db_error_ptr(), e.db_error_len()))}`);
    frames.add(hash(new Uint8Array(e.memory.buffer, e.db_frame_ptr(), e.db_frame_len())));
    const pcm = new Float32Array(e.memory.buffer, e.db_audio_ptr(), e.db_audio_len());
    for (const sample of pcm) { assert.ok(Number.isFinite(sample)); peak = Math.max(peak, Math.abs(sample)); }
    sampleFrames += pcm.length / 2;
    e.db_audio_clear();
  }
  assert.ok(frames.size > 1, `${name}: static video`);
  if (name !== 'neon-stadium') assert.ok(e.db_gpu_dispatches() > 1, `${name}: no GPU dispatches`);
  assert.equal(e.db_audio_overruns(), 0);
  if (name !== 'pelican') assert.ok(peak > 0);
  runs.push({ name, frames: 120, profile: 'dynamic-1', cartridgeSha256: hash(cart), payloadBytes: cart.length - 32,
    uniqueFrames: frames.size, gpuDispatches: e.db_gpu_dispatches(), sampleFrames, peak, audioOverruns: e.db_audio_overruns(), passed: true });
}
const report = { ok: true, checkedAt: new Date().toISOString(), origin,
  backend: 'downloaded-production-wasm', checks, runs };
mkdirSync('artifacts/pack', { recursive: true });
writeFileSync('artifacts/pack/deployment-verification.json', JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({ ok: report.ok, assets: checks.length, wasmSha256: hash(wasm), runs }, null, 2));
