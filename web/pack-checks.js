import { runGpuChecks } from './gpu-checks.js';
const report = document.querySelector('#report'), status = document.querySelector('#status');
async function workerCheck(name, audio) {
  const source = await (await fetch(`./pack-fixtures/${name}.packed.asm`)).text();
  const worker = new Worker('./machine-worker.js', { type: 'module' });
  let timer; const hashes = new Set();
  try {
    return await new Promise((resolve, reject) => {
      timer = setTimeout(() => reject(new Error(`${name}: worker deadline`)), 30000);
      worker.onerror = event => reject(new Error(event.message));
      worker.onmessage = ({ data }) => {
        if (data.type === 'ready') worker.postMessage({ type: 'assemble', source, autoPlay: true });
        if (data.type === 'error' || data.type === 'init-error') reject(new Error(data.message));
        if (data.type === 'state') {
          if (data.frame) {
            let hash = 2166136261;
            for (const byte of data.frame) hash = Math.imul(hash ^ byte, 16777619) >>> 0;
            hashes.add(hash);
            document.querySelector('#frame').getContext('2d').putImageData(new ImageData(new Uint8ClampedArray(data.frame), 160, 120), 0, 0);
          }
          if (data.frameCount >= 120) {
            if (data.profileCode !== 4 || data.backend.active !== 'webgpu' || hashes.size < 2 || data.gpu.dispatches < 10 ||
              (audio && (data.audio.backend !== 'webgpu' || data.audio.peak <= 0 || data.audio.overruns !== 0))) {
              reject(new Error(`${name}: unexpected state ${JSON.stringify(data)}`)); return;
            }
            resolve({ name, profile: data.profile, frames: data.frameCount, payload: data.payloadSize, pc: data.pc,
              gpu: data.gpu, audio: data.audio, backend: data.backend, changedFrames: hashes.size, wasmSha256: data.wasmSha256, passed: true });
          }
        }
      };
    });
  } finally { clearTimeout(timer); worker.terminate(); }
}
try {
  const hardware = await runGpuChecks();
  report.textContent = JSON.stringify({ hardware, workers: 'running' }, null, 2);
  const workers = [await workerCheck('dynamic', false), await workerCheck('astra', true)];
  report.textContent = JSON.stringify({ ok: true, hardware, workers }, null, 2);
  status.textContent = 'PASS: hardware checks, changing RAM kernels, and packed ASTRA graphics/audio';
} catch (error) {
  status.textContent = 'FAIL'; report.textContent += `\n${error.stack ?? error}`;
}
