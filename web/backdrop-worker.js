// Runs examples/backdrop.asm on its own instance of the machine and tiles its 160×120 frames across an OffscreenCanvas
// behind the homepage. Its GPU kernels run through the same WebGPU backend as the demo player. Without WebGPU the
// reference interpreter would cost a host CPU core, so the page then shows one still frame instead.
// The cartridge renders open ground as exact mid grey; each pixel's difference from that grey is added, scaled down,
// to the page colour, so the scene reads as a faint relief in light and dark themes.
// Messages in: init {canvas, width, height, scale, theme, running}, resize {width, height}, theme {theme}, run {running}.
// Messages out: ready {payloadBytes, live}, error {message}.
import { WebGpuBackend } from './gpu-webgpu.js';

const FRAME_TICKS = 204_800;
const W = 160, H = 120, GROUND = 127.5;
const PRESENT_MS = 1000 / 30; // the machine keeps 60 Hz virtual time; the page is repainted at up to 30 fps

let wasm, memory, ctx, tile, tileCtx, image, accelerator = null;
let scale = 3, theme = { room: [236, 235, 230], strength: .3 };
let running = false, live = false, timer = null, lastRun = 0, debt = 0, busy = false;

const text = (ptr, len) => new TextDecoder().decode(new Uint8Array(memory.buffer, ptr, len));
const machineError = () => text(wasm.db_error_ptr(), wasm.db_error_len());
const copy = (ptr, len) => new Uint8Array(memory.buffer.slice(ptr, ptr + len));
const ticks = () => (BigInt(wasm.db_ticks_hi() >>> 0) << 32n) | BigInt(wasm.db_ticks_lo() >>> 0);

async function init(data) {
  ctx = data.canvas.getContext('2d'); // transparent until the first frame, so a failed start leaves the page as it was
  scale = data.scale || 3;
  theme = data.theme;
  resize(data.width, data.height);
  const [bytes, source, gpu] = await Promise.all([
    fetch(new URL('./machine.wasm', import.meta.url)).then(r => { if (!r.ok) throw new Error(`machine.wasm HTTP ${r.status}`); return r.arrayBuffer(); }),
    fetch(new URL('./examples/backdrop.asm', import.meta.url)).then(r => { if (!r.ok) throw new Error(`backdrop.asm HTTP ${r.status}`); return r.text(); }),
    WebGpuBackend.create(),
  ]);
  wasm = (await WebAssembly.instantiate(bytes, {})).instance.exports;
  memory = wasm.memory;
  if (wasm.db_abi_version() !== 1) throw new Error('Unsupported machine ABI');
  const input = new TextEncoder().encode(source);
  const at = wasm.db_input_ptr(); // the first call may grow memory, so take the buffer afterwards
  new Uint8Array(memory.buffer, at, input.length).set(input);
  if (wasm.db_assemble(input.length) !== 0 || wasm.db_load_assembled() !== 0) throw new Error(machineError());
  accelerator = gpu.backend;
  live = !!accelerator && wasm.db_gpu_set_external(1) === 0;
  tile = new OffscreenCanvas(W, H);
  tileCtx = tile.getContext('2d');
  image = tileCtx.createImageData(W, H);
  // the first finished page reaches video after a few frames
  for (let i = 0; i < 4; i++) await runMachineFrame();
  present();
  self.postMessage({ type: 'ready', payloadBytes: wasm.db_payload_size() >>> 0, live });
  if (data.running) setRunning(true);
}

// One video frame of machine time. Pending GPU jobs go to WebGPU; any failure resumes them in the reference
// interpreter, and the backdrop then stops animating after this frame.
async function runMachineFrame() {
  const end = ticks() + BigInt(FRAME_TICKS);
  while (ticks() < end || wasm.db_gpu_external_pending()) {
    if (wasm.db_gpu_external_pending()) {
      const read = offset => wasm.db_gpu_read_reg(offset) >>> 0;
      const descriptor = {
        rom: copy(wasm.db_rom_ptr(), wasm.db_rom_len()), ram: copy(wasm.db_ram_ptr(), wasm.db_ram_len()), allowRamCode: false,
        codeBase: read(0), codeLength: read(4), width: read(8), height: read(12), processor: 'gpu',
        bindings: Array.from({ length: 4 }, (_, i) => ({ base: read(0x40 + 16 * i), len: read(0x44 + 16 * i), flags: read(0x48 + 16 * i) })),
      };
      try {
        const result = await accelerator.dispatch(descriptor, descriptor.ram, Uint32Array.from({ length: 16 }, (_, i) => read(0x100 + 4 * i)));
        const ramLength = wasm.db_ram_len();
        for (const write of result.writes) if (write.offset < 0 || write.offset + write.bytes.length > ramLength) throw new Error('Invalid accelerated output range.');
        const ram = new Uint8Array(memory.buffer, wasm.db_ram_ptr(), ramLength);
        for (const write of result.writes) ram.set(write.bytes, write.offset);
        if (wasm.db_gpu_external_complete() !== 0) throw new Error(machineError());
      } catch {
        wasm.db_gpu_set_external(0);
        live = false;
      }
      continue;
    }
    const remaining = end - ticks();
    if (remaining <= 0n) break;
    const code = wasm.db_run(Number(remaining));
    if (code === 3) throw new Error(machineError());
    if (code === 0 || code === 2) break;
  }
}

function resize(width, height) {
  ctx.canvas.width = Math.max(1, Math.round(width));
  ctx.canvas.height = Math.max(1, Math.round(height));
  present();
}

function present() {
  if (!image) return;
  const src = new Uint8Array(memory.buffer, wasm.db_frame_ptr(), wasm.db_frame_len()), dst = image.data;
  const [r0, g0, b0] = theme.room, k = theme.strength;
  for (let i = 0; i < src.length; i += 4) {
    dst[i] = r0 + (src[i] - GROUND) * k; dst[i + 1] = g0 + (src[i + 1] - GROUND) * k; dst[i + 2] = b0 + (src[i + 2] - GROUND) * k; dst[i + 3] = 255;
  }
  tileCtx.putImageData(image, 0, 0);
  const pattern = ctx.createPattern(tile, 'repeat');
  pattern.setTransform(new DOMMatrix().scaleSelf(scale, scale));
  ctx.imageSmoothingEnabled = false;
  ctx.fillStyle = pattern;
  ctx.fillRect(0, 0, ctx.canvas.width, ctx.canvas.height);
}

async function tick() {
  timer = null;
  if (!running || !live) return;
  busy = true;
  try {
    const now = performance.now();
    debt = Math.min(debt + (now - lastRun) * 60 / 1000, 2); // at most two machine frames per repaint
    lastRun = now;
    let ran = false;
    while (debt >= 1 && live) { await runMachineFrame(); debt -= 1; ran = true; }
    if (ran) present();
  } catch (error) {
    live = false;
    self.postMessage({ type: 'error', message: error.message || String(error) });
  } finally { busy = false; }
  if (running && live) timer = setTimeout(tick, PRESENT_MS);
}

function setRunning(on) {
  running = on && !!wasm;
  if (timer !== null) { clearTimeout(timer); timer = null; }
  if (running && live && !busy) { lastRun = performance.now(); debt = 1; tick(); }
}

self.onmessage = ({ data }) => {
  switch (data.type) {
    case 'init': init(data).catch(error => self.postMessage({ type: 'error', message: error.message || String(error) })); break;
    case 'resize': if (ctx) resize(data.width, data.height); break;
    case 'theme': theme = data.theme; present(); break;
    case 'run': setRunning(data.running); break;
  }
};
