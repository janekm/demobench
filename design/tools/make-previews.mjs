// Captures real preview media for the design mockups from the headless WASM machine.
// Output: design/previews/<id>.png poster, src/<id>.asm, <id>.gif, <id>-kNN.png keyframes, <id>-bytes.png, records/<id>.json and data.js.
// Usage: node design/tools/make-previews.mjs [--only id,id]   (data.js is rebuilt from every existing record)
import { readFileSync, writeFileSync, mkdirSync, rmSync, existsSync, copyFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { createMachine, WIDTH, HEIGHT } from '../../scripts/wasm-host.mjs';
import { png } from '../../scripts/png.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const out = resolve(root, 'design/previews');
const recordsDir = resolve(out, 'records'), srcDir = resolve(out, 'src');
mkdirSync(recordsDir, { recursive: true });
mkdirSync(srcDir, { recursive: true });
const args = process.argv.slice(2);
const only = args.includes('--only') ? args[args.indexOf('--only') + 1].split(',') : null;

// Daybreak: eight 450-frame scenes; the reel keeps a 96-frame window from each (title and end text included).
const DAYBREAK_SCENES = [
  ['Night spheres, title', 250], ['Neon tunnel', 600], ['Menger sponge, pre-dawn', 1050], ['Purple tunnel, roll', 1500],
  ['Sunrise, bouncing spheres', 1950], ['Sponge from below, morning', 2400], ['Pink neon tunnel', 2850], ['Daylight, BY OPUS', 3400],
];
const ASTRA_SCENES = [
  ['Ignition', 42], ['Choir of glass', 552], ['Hyperdrive', 1032], ['Chaos bloom', 1452],
  ['Orbital resonance', 1992], ['Crystal return', 2412], ['Event horizon', 2832], ['Into the infinite', 3252],
];
// Carpet: [name, start frame] of 96-frame windows at the flight's landmarks (the loop is 2,880 frames).
const CARPET_SCENES = [
  ['Northern bay', 60], ['Castle towers', 336], ['West-coast islands', 828], ['Mana orbs', 1104],
  ['Volcano erupts', 1476], ['Eastern coast', 2160], ['Balloon ahead', 2328], ['Fireball blast', 2424],
];
// ELSEWHERE: [name, shot start frame, window start] for its eight shots (100 BPM: one bar is 144 frames; the film loops at 3,456).
const ELSEWHERE_SCENES = [
  ['City', 0, 280], ['Drive', 576, 700], ['Drive, close', 864, 950], ['The lab', 1152, 1450],
  ['The strike', 1728, 1908], ['Elsewhere', 2016, 2280], ['The beast', 2592, 2730], ['The traveller watches', 3024, 3180],
];
// LIMIT SET: eight 450-frame scenes, one window each.
const LIMIT_SET_SCENES = [
  ['Flat space, title', 200], ['Space curves', 560], ['{4,3,5}', 1040], ['{5,3,4}', 1500],
  ['{4,3,6}', 1900], ['{4,3,∞}', 2560], ['Indra’s pearls', 2800], ['Outside, OPUS', 3380],
];
// LIGHTCONE: nine 384-frame scenes (the ninth returns to the star and is left out), one window each.
// KOI: nine 400-frame scenes; one window from each except the tilt back down.
const KOI_SCENES = [
  ['A drop falls', 150], ['KOI pressed into the water', 470], ['Tilt to the sky', 1080], ['Wind', 1750],
  ['Rain shower', 2150], ['Koi rise', 2550], ['Golden hour', 2950], ['Dusk', 3330],
];
const LIGHTCONE_SCENES = [
  ['Light echo', 110], ['Kick echoes', 580], ['Clap echoes', 1048], ['Relativistic flight', 1242],
  ['Terrell rotation', 1662], ['Photoelastic disks', 2022], ['Force-chain surges', 2382], ['0.99 c', 2922],
];

// frames: virtual frames to run; step: keep every Nth frame; fps: GIF rate; hold: seconds to hold the last frame;
// skip: leading virtual frames to leave out (before the first presented image); dither: FFmpeg paletteuse mode override;
// segments: [start, end) virtual-frame windows to keep instead of the whole run; poster: keyframe used as the static
// browse image (default: the finished picture for demos that halt, otherwise the middle keyframe).
const DEMOS = [
  { id: 'astra', title: 'ASTRA', subtitle: '4K intro · 60 s', author: 'Astra', frames: 3600, step: 4, fps: 15,
    description: 'An eight-chapter journey through luminous geometry, recursive crystals, hyperspace tunnels and Julia fractals, with an original 128 BPM stereo synth score.',
    segments: ASTRA_SCENES.map(([, at]) => [at, at + 96]), poster: 0,
    scenes: ASTRA_SCENES.map(([name], i) => ({ name, at: i * 7.5 })) },
  { id: 'daybreak', title: 'Daybreak', subtitle: '4K intro · 60 s', author: 'Opus', source: '../opus_demo/daybreak.asm', frames: 3600, step: 4, fps: 15,
    description: 'A journey from night to full daylight in eight scenes, cut to an original 128 BPM electronic track.',
    segments: DAYBREAK_SCENES.map(([, at]) => [at, at + 96]), poster: 0,
    scenes: DAYBREAK_SCENES.map(([name], i) => ({ name, at: i * 7.5 })) },
  // one full 20-second camera swing, starting after the first presented image
  { id: 'pelican', title: 'Pelican', subtitle: 'seaside ride · calypso', author: 'Opus 5.5', frames: 1216, skip: 16, step: 4, fps: 15,
    description: 'A ray-traced pelican riding a bicycle along a seaside promenade: pedalling legs by two-bone IK, sun shadows and a chrome clear coat, a foam line washing in every 5 s, a pastel harbour town and drifting sailboats across the bay, and a 100 BPM calypso with steelpan, bass, shaker and surf. Packed to 4,088 bytes.' },
  // three bars of the full arrangement after the four intro bars (136 BPM: one bar is about 106 frames)
  { id: 'supersaw', title: 'Supersaw', subtitle: 'Sandstorm-style riff · 136 BPM', author: 'Opus 5.5', frames: 758, skip: 440, step: 4, fps: 15, dither: 'none', // flat LED colours: noise-free frames compress far better
    description: 'A JP-8000-style supersaw (three seven-voice PolyBLEP layers, 21 saws) playing a Sandstorm-style riff at 136 BPM, with a kick-ducked FDN reverb, ping-pong delay, bass and drums. The GPU runs 40 Goertzel filters over the live mix to draw an LED spectrum analyser above the waveform.' },
  { id: 'carpet', title: 'Carpet', subtitle: 'flying-carpet flight · 48 s', author: 'Opus 5.5', frames: 2880, step: 4, fps: 15,
    description: 'A 48-second flight on a flying carpet over a procedurally generated, ray-marched archipelago: a castle with golden domes, mana orbs, an erupting volcano and a fireball for the hot-air balloon, scored in D hijaz with oud, ney and darbuka. An homage to Bullfrog’s Magic Carpet, packed to 4,093 bytes.',
    segments: CARPET_SCENES.map(([, at]) => [at, at + 96]), poster: 4,
    scenes: CARPET_SCENES.map(([name, at]) => ({ name, at: at / 60 })) },
  { id: 'elsewhere', title: 'Elsewhere', subtitle: 'vector film · 58 s', author: 'Opus 5.5', frames: 3456, step: 4, fps: 15, readme: '../opus_demo/elsewhere/README.md',
    description: 'A vector film in the style of Éric Chahi’s Another World. A red sports car drives through a rain-soaked city at night to a laboratory tower. Lightning strikes the mast, and in a white flash the film cuts to another world, where a traveller on a cliff watches a beast walk across the face of a huge planet. Flat polygons are drawn by a two-pass GPU span renderer into 8-bit indexed pages, and the palette does the lightning and the fades. Original 100 BPM soundtrack, packed to 4,084 bytes.',
    segments: ELSEWHERE_SCENES.map(([, , at]) => [at, at + 96]), poster: 2,
    scenes: ELSEWHERE_SCENES.map(([name, at]) => ({ name, at: at / 60 })) },
  { id: 'limit-set', title: 'LIMIT SET', subtitle: 'hyperbolic space · 60 s', author: 'Opus 5.5', frames: 3600, step: 4, fps: 15, readme: '../opus_demo/limit/README.md',
    description: 'A flight through hyperbolic space, ray traced per pixel. One honeycomb parameter is swept from a flat cubic lattice through the regular hyperbolic honeycombs {4,3,5}, {5,3,4} and {4,3,6}, past infinity, until space falls apart into the fractal limit set of its own symmetry group. The finale shows the whole universe from outside, as a ball painted with the limit set. Original 128 BPM soundtrack in D minor, packed to 4,074 bytes.',
    segments: LIMIT_SET_SCENES.map(([, at]) => [at, at + 96]), poster: 2,
    scenes: LIMIT_SET_SCENES.map(([name], i) => ({ name, at: i * 7.5 })) },
  { id: 'lightcone', title: 'Lightcone', subtitle: 'slow light · 58 s', author: 'Opus 5.5', frames: 3456, step: 4, fps: 15, readme: '../opusdemo2/README.md',
    description: 'Light slowed down so you can watch it work: light echoes sweeping through a dust nebula, a flight to 0.99 c with aberration and Doppler shift, a title turned by light-travel time (Terrell rotation), and force chains glowing in photoelastic glass disks. Original 150 BPM hard techno, packed to 4,071 bytes.',
    segments: LIGHTCONE_SCENES.map(([, at]) => [at, at + 96]), poster: 5,
    scenes: LIGHTCONE_SCENES.map(([name], i) => ({ name, at: Math.round(i * 6.4 * 10) / 10 })) },
  { id: 'koi', title: 'Koi', subtitle: 'koi pond · 60 s', author: 'Opus 5.5', source: '../opusdemo2/koi/koi.packed.asm', frames: 3600, step: 4, fps: 15, readme: '../opusdemo2/koi/README.md',
    description: 'A koi pond seen from above and at a slant, from morning light through wind and a rain shower to a golden evening. The water is a GPU wave equation plus Gerstner waves and ripples; refraction, Beer–Lambert absorption and caustics traced back to the pond floor light a school of koi that swim as boids. The title is pressed into the surface and ripples away. Silent, packed to 4,061 bytes.',
    segments: KOI_SCENES.map(([, at]) => [at, at + 96]), poster: 1,
    scenes: KOI_SCENES.map(([name, at]) => ({ name, at: Math.round(at / 6) / 10 })) },
  // one full 20-second camera orbit, starting after extraction
  { id: 'pelican-pedal-club', title: 'Pelican Pedal Club', subtitle: 'beach ride · 120 BPM', author: 'Sol 6.1', source: '../sol61demo/artifacts/pelican.packed.asm', frames: 1216, skip: 16, step: 4, fps: 15, readme: '../sol61demo/README.md',
    description: 'A white pelican in a coral cap pedals a turquoise bicycle along the beach, past a palm tree and a striped parasol, while the camera circles it. Fifty analytic ellipsoids make up the rider, bike and scenery; animated ocean normals reflect the clouds and break the sun into a moving golden trail. A 120 BPM stereo loop of plucks, bass and kick runs through a cross-feedback delay. Packed to 4,045 bytes.' },
  // the first 20 seconds of its uncut 60-second camera move
  { id: 'pelican-bicycle', title: 'Pelican on a Bicycle', subtitle: 'golden-hour beach · 88 BPM', author: 'Sonnet 5.5', source: '../sonnet_demo_2/deliverable/pelican_bicycle.packed.asm', frames: 1216, skip: 16, step: 4, fps: 15,
    description: 'A pelican in sunglasses rides a red beach cruiser in circles on the sand at golden hour, pedalling once per bar of the music. Forty-nine capsules and ray-marched tyres, hard ray-traced shadows, a glittering sea with Fresnel reflections and a tyre track in the sand; the camera swings, dollies and rises without a cut. An eight-voice FM and noise synth plays a G-major loop at 88 BPM with a ping-pong echo. Packed to 4,094 bytes.' },
  { id: 'aurora', title: 'Aurora', subtitle: 'indexed colour', frames: 240, step: 2, fps: 30 },
  { id: 'rgb-study', title: 'RGB study', subtitle: 'true colour', frames: 90, step: 1, fps: 30, hold: 2.5 },
  { id: 'ray-tracer', title: 'Ray tracer', subtitle: 'spheres & reflections', frames: 480, step: 6, fps: 20, hold: 2.5 },
  { id: 'ray-tracer-r1', title: 'Ray tracer', subtitle: 'revision 1', source: 'artifacts/ray-tracer-before.asm', frames: 480, step: 6, fps: 20, hold: 2.5 },
  { id: 'gpu-ray-tracer', title: 'GPU ray tracer', subtitle: 'real-time reflections', frames: 360, step: 3, fps: 20 },
  { id: 'gpu-ray-tracer-fast', title: 'GPU ray tracer', subtitle: '80×60 rays', source: 'examples/gpu-ray-tracer.asm', frames: 360, step: 3, fps: 20,
    transform: (src) => src.replace(/\.equ PIXEL_SHIFT, 0/, '.equ PIXEL_SHIFT, 1') },
  { id: 'signal-garden', title: 'Signal garden', subtitle: 'programmable audio', frames: 480, step: 4, fps: 15 },
  { id: 'neon-stadium', title: 'Neon stadium', subtitle: 'supersaw & drums', frames: 900, step: 4, fps: 15 },
];
const KEYFRAMES = 8;
const FORMAT = { 0: 'I1', 1: 'I2', 2: 'I4', 3: 'I8', 4: 'RGB888' };

const b64i8 = (arr) => Buffer.from(Int8Array.from(arr, (v) => Math.max(-127, Math.min(127, Math.round(v * 127)))).buffer).toString('base64');
const b64u8 = (arr) => Buffer.from(Uint8Array.from(arr, (v) => Math.max(0, Math.min(255, Math.round(v * 255))))).toString('base64');
const visible = (frame) => frame.some((v, i) => i % 4 !== 3 && v > 8);

// Indexed frames map without dithering; RGB888 frames use error diffusion instead of a visible ordered pattern.
function gif(id, frames, fps, holdFrames, rgb, dither) {
  const raw = resolve(out, `${id}.rgba`);
  const seq = holdFrames ? [...frames, ...Array(holdFrames).fill(frames.at(-1))] : frames;
  writeFileSync(raw, Buffer.concat(seq.map((f) => Buffer.from(f))));
  execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgba', '-s', `${WIDTH}x${HEIGHT}`, '-r', String(fps), '-i', raw,
    '-vf', `split[a][b];[a]palettegen=stats_mode=full:max_colors=256[p];[b][p]paletteuse=dither=${dither ?? (rgb ? 'sierra2_4a' : 'none')}:diff_mode=rectangle`,
    '-loop', '0', resolve(out, `${id}.gif`)]);
  rmSync(raw);
}

// One pixel per payload byte, 64 bytes per row, with a transparent unused-capacity tail up to 4,096 bytes.
function bytemap(id, payload) {
  const cols = 64, rows = 64, rgba = new Uint8Array(cols * rows * 4);
  for (let i = 0; i < cols * rows; i++) {
    const v = i < payload.length ? payload[i] : -1;
    rgba.set(v < 0 ? [0, 0, 0, 0] : [v, v, v, 255], i * 4);
  }
  writeFileSync(resolve(out, `${id}-bytes.png`), png(cols, rows, rgba));
}

// The author's README becomes the demo's notes page: the local file table and build instructions are left out.
function notes(demo) {
  const text = readFileSync(resolve(root, demo.readme), 'utf8').replace(/\r\n/g, '\n');
  const kept = text.split(/\n(?=## )/).filter((s) => !/^## (Build|Rebuilding|Play|Reproduce)\b/.test(s)).join('\n')
    .replace(/\n\| file \| what \|\n(\|.*\n)+/, '\n').replace(/\n{3,}/g, '\n\n');
  mkdirSync(resolve(out, 'notes'), { recursive: true });
  writeFileSync(resolve(out, 'notes', `${demo.id}.md`), kept.trimEnd() + '\n');
  return `notes/${demo.id}.md`;
}

function capture(demo) {
  const t0 = performance.now();
  const sourcePath = demo.source ?? `examples/${demo.id}.asm`;
  let source = readFileSync(resolve(root, sourcePath), 'utf8');
  if (demo.transform) source = demo.transform(source);
  writeFileSync(resolve(srcDir, `${demo.id}.asm`), source); // exact source, loadable by the studio viewer
  const machine = createMachine();
  const cartridge = machine.assemble(source);
  machine.load(cartridge);
  const keep = (f) => f > (demo.skip ?? 0) && (!demo.segments || demo.segments.some(([a, b]) => f >= a && f < b));
  const kept = [], keptAt = [], rms = [], scope = [], wave = [];
  let firstVisible = null, maxGpu = 0, sumL = 0, sumR = 0, n = 0, audioPeak = 0;
  for (let f = 1; f <= demo.frames; f++) {
    machine.runFrames(1);
    const pcm = machine.audio();
    for (let i = 0; i < pcm.length; i += 2) { sumL += pcm[i] ** 2; sumR += pcm[i + 1] ** 2; n++; audioPeak = Math.max(audioPeak, Math.abs(pcm[i]), Math.abs(pcm[i + 1])); }
    if (pcm.length) {
      let lo = 1, hi = -1;
      for (let i = 0; i < pcm.length; i += 2) { const m = (pcm[i] + pcm[i + 1]) / 2; lo = Math.min(lo, m); hi = Math.max(hi, m); }
      wave.push(lo, hi);
    }
    const gpu = machine.info().gpu.frameBudgetPercent;
    if (gpu) maxGpu = Math.max(maxGpu, gpu);
    if (firstVisible === null && visible(machine.frame())) firstVisible = f;
    if (f % demo.step === 0) {
      // RMS per kept GIF frame, averaged over its step window, so meters line up with the reel.
      if (keep(f)) {
        if (n) rms.push(Math.sqrt(sumL / n), Math.sqrt(sumR / n));
        for (let i = 0; i < Math.min(pcm.length, 512); i += 4) scope.push(pcm[i], pcm[i + 1]);
        kept.push(machine.frame()); keptAt.push(f);
      }
      sumL = sumR = n = 0;
    }
  }
  const info = machine.info();
  gif(demo.id, kept, demo.fps, Math.round((demo.hold ?? 0) * demo.fps), info.format === 4, demo.dither);
  const picks = demo.segments
    ? demo.segments.map(([a, b]) => keptAt.findIndex((f) => f >= (a + b) / 2))
    : Array.from({ length: KEYFRAMES }, (_, k) => Math.round(k * (kept.length - 1) / (KEYFRAMES - 1)));
  const keyframes = picks.map((index, k) => {
    const name = `${demo.id}-k${String(k).padStart(2, '0')}.png`;
    writeFileSync(resolve(out, name), png(WIDTH, HEIGHT, kept[index]));
    return { file: name, frame: keptAt[index] };
  });
  const poster = demo.poster ?? (info.status === 2 ? keyframes.length - 1 : keyframes.length >> 1);
  copyFileSync(resolve(out, keyframes[poster].file), resolve(out, `${demo.id}.png`));
  const payload = cartridge.subarray(32);
  bytemap(demo.id, payload);
  const lines = source.split('\n');
  const peak = rms.length ? Math.max(...rms) : 0;
  const record = {
    id: demo.id, title: demo.title, subtitle: demo.subtitle, author: demo.author ?? null, source: sourcePath,
    profile: info.profile, format: FORMAT[info.format] ?? String(info.format),
    engines: ['CPU', info.gpu.dispatches ? 'GPU' : null, info.audio.blocks ? 'SPU' : null].filter(Boolean),
    payloadBytes: info.payloadBytes, cartridgeBytes: cartridge.length,
    cartridgeSha256: createHash('sha256').update(cartridge).digest('hex'),
    rgbaSha256: info.rgbaSha256, wasmSha256: info.wasmSha256,
    frames: demo.frames, seconds: demo.frames / 60, firstVisibleFrame: firstVisible,
    halted: info.status === 2, gpuDispatches: info.gpu.dispatches, gpuBudgetPercent: maxGpu || null,
    spuBlocks: info.audio.blocks, audioPeak,
    lines: lines.length, instructions: lines.filter((l) => /^\s+[a-z]/.test(l.replace(/;.*/, ''))).length,
    notes: lines.filter((l) => l.startsWith(';')).map((l) => l.replace(/^;\s?/, '').trim()).filter((l) => /[a-z]/i.test(l)).slice(0, 5),
    excerpt: lines.filter((l) => l.trim() && !l.startsWith(';')).slice(0, 18).join('\n'),
    description: demo.description ?? null, scenes: demo.scenes ?? null,
    poster: `${demo.id}.png`, gif: `${demo.id}.gif`, gifFps: demo.fps, gifFrames: kept.length, keyframes, bytes: `${demo.id}-bytes.png`,
    payloadHex: Buffer.from(payload).toString('hex'),
    audio: rms.length ? { rms: b64u8(rms.map((v) => v / Math.max(peak, 1e-6))), wave: b64i8(wave), scope: b64i8(scope),
      fps: demo.fps, scopeLen: 128, scopeStereo: true } : null,
  };
  writeFileSync(resolve(recordsDir, `${demo.id}.json`), JSON.stringify(record));
  console.log(`${demo.id}: ${kept.length} frames, ${info.payloadBytes} B, ${((performance.now() - t0) / 1000).toFixed(1)} s`);
}

for (const demo of DEMOS) if (!only || only.includes(demo.id)) capture(demo);
// Notes are refreshed on every run, so README edits need no new capture.
for (const demo of DEMOS.filter((d) => d.readme)) {
  const path = resolve(recordsDir, `${demo.id}.json`);
  if (existsSync(path)) writeFileSync(path, JSON.stringify({ ...JSON.parse(readFileSync(path, 'utf8')), readme: notes(demo) }));
}
const records = DEMOS.map((d) => resolve(recordsDir, `${d.id}.json`)).filter(existsSync).map((p) => JSON.parse(readFileSync(p, 'utf8')));
writeFileSync(resolve(out, 'data.js'), `// Generated by design/tools/make-previews.mjs from the headless WASM machine.\nwindow.DEMOS = ${JSON.stringify(records, null, 1)};\n`);
console.log(`data.js: ${records.length} demos`);
