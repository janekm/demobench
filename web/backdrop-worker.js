// Runs examples/backdrop.asm on its own instance of the reference machine and tiles its 160×120 frames across an
// OffscreenCanvas behind the homepage. The cartridge's colours are blended into the page colour here, so the pattern
// reads as a faint texture in light and dark themes without CSS blend modes.
// Messages in: init {canvas, width, height, scale, theme}, resize {width, height}, theme {theme}, run {running}.
// Messages out: ready {payloadBytes}, error {message}.
const FRAME_TICKS = 204_800;
const W = 160, H = 120;
const PRESENT_MS = 1000 / 30; // the machine keeps 60 Hz virtual time; the page is repainted at 30 fps

let wasm, memory, ctx, tile, tileCtx, image, pattern = null;
let scale = 3, theme = { dark: false, room: [236, 235, 230], line: 1, glow: 1 };
let running = false, timer = null, lastRun = 0, debt = 0, dirty = true;

function text(ptr, len) { return new TextDecoder().decode(new Uint8Array(memory.buffer, ptr, len)); }
function upload(bytes) {
  const ptr = wasm.db_input_ptr();
  new Uint8Array(memory.buffer, ptr, bytes.length).set(bytes);
  return bytes.length;
}

async function init(data) {
  ctx = data.canvas.getContext('2d', { alpha: false });
  scale = data.scale || 3;
  theme = data.theme;
  resize(data.width, data.height);
  const [bytes, source] = await Promise.all([
    fetch(new URL('./machine.wasm', import.meta.url)).then(r => { if (!r.ok) throw new Error(`machine.wasm HTTP ${r.status}`); return r.arrayBuffer(); }),
    fetch(new URL('./examples/backdrop.asm', import.meta.url)).then(r => { if (!r.ok) throw new Error(`backdrop.asm HTTP ${r.status}`); return r.text(); }),
  ]);
  wasm = (await WebAssembly.instantiate(bytes, {})).instance.exports;
  memory = wasm.memory;
  if (wasm.db_abi_version() !== 1) throw new Error('Unsupported machine ABI');
  if (wasm.db_assemble(upload(new TextEncoder().encode(source))) !== 0) throw new Error(text(wasm.db_error_ptr(), wasm.db_error_len()));
  if (wasm.db_load_assembled() !== 0) throw new Error(text(wasm.db_error_ptr(), wasm.db_error_len()));
  // The CPU draws the pattern in its first few frames and enables video afterwards; start from a finished picture.
  for (let i = 0; i < 12; i++) wasm.db_run(FRAME_TICKS);
  tile = new OffscreenCanvas(W, H);
  tileCtx = tile.getContext('2d');
  image = tileCtx.createImageData(W, H);
  self.postMessage({ type: 'ready', payloadBytes: wasm.db_payload_size() >>> 0 });
  present();
  if (data.running) setRunning(true);
}

function resize(width, height) {
  ctx.canvas.width = Math.max(1, Math.round(width));
  ctx.canvas.height = Math.max(1, Math.round(height));
  pattern = null;
  dirty = true;
}

// Dark theme: screen the cartridge colour onto the page colour. Light theme: keep each colour's hue but invert its
// brightness (black background → white), then multiply. Either way the black background leaves the page untouched.
// Dim pixels (the arcs) are mixed in with theme.line and bright ones (the glow) with theme.glow, so the glow stays soft.
function blend(src, dst) {
  const [r0, g0, b0] = theme.room;
  for (let i = 0; i < src.length; i += 4) {
    const r = src[i], g = src[i + 1], b = src[i + 2], lum = Math.max(r, g, b) / 255;
    const k = theme.line + (theme.glow - theme.line) * Math.min(1, lum * lum * 1.6);
    let r1, g1, b1;
    if (theme.dark) {
      r1 = 255 - (255 - r0) * (255 - r) / 255; g1 = 255 - (255 - g0) * (255 - g) / 255; b1 = 255 - (255 - b0) * (255 - b) / 255;
    } else {
      const lift = 255 - Math.max(r, g, b);
      r1 = r0 * (lift + r) / 255; g1 = g0 * (lift + g) / 255; b1 = b0 * (lift + b) / 255;
    }
    dst[i] = r0 + (r1 - r0) * k; dst[i + 1] = g0 + (g1 - g0) * k; dst[i + 2] = b0 + (b1 - b0) * k; dst[i + 3] = 255;
  }
}

function present() {
  if (!wasm) return;
  const frame = new Uint8Array(memory.buffer, wasm.db_frame_ptr(), wasm.db_frame_len());
  blend(frame, image.data);
  tileCtx.putImageData(image, 0, 0);
  pattern = ctx.createPattern(tile, 'repeat');
  pattern.setTransform(new DOMMatrix().scaleSelf(scale, scale));
  ctx.imageSmoothingEnabled = false;
  ctx.fillStyle = pattern;
  ctx.fillRect(0, 0, ctx.canvas.width, ctx.canvas.height);
  dirty = false;
}

function tick() {
  timer = null;
  if (!running) return;
  const now = performance.now();
  debt = Math.min(debt + (now - lastRun) * 60 / 1000, 4); // at most four frames of catch-up after a stall
  lastRun = now;
  let ran = false;
  while (debt >= 1) { wasm.db_run(FRAME_TICKS); debt -= 1; ran = true; }
  if (ran || dirty) present();
  timer = setTimeout(tick, PRESENT_MS);
}

function setRunning(on) {
  running = on && !!wasm;
  if (timer !== null) { clearTimeout(timer); timer = null; }
  if (running) { lastRun = performance.now(); debt = 0; tick(); }
  else if (dirty) present();
}

self.onmessage = ({ data }) => {
  try {
    switch (data.type) {
      case 'init': init(data).catch(error => self.postMessage({ type: 'error', message: error.message || String(error) })); break;
      case 'resize': resize(data.width, data.height); if (!running) present(); break;
      case 'theme': theme = data.theme; dirty = true; if (!running) present(); break;
      case 'run': setRunning(data.running); break;
    }
  } catch (error) {
    self.postMessage({ type: 'error', message: error.message || String(error) });
  }
};
