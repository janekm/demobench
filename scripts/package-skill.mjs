import { copyFileSync, mkdirSync, readFileSync, writeFileSync, accessSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { parseArgs } from 'node:util';

const root = fileURLToPath(new URL('../', import.meta.url));
const { values } = parseArgs({ options: { kit: { type: 'string', default: '../demobench-agent-kit' } } });
const skill = resolve(root, values.kit);
// Refresh an existing standalone kit; the kit owns its skill and distribution tooling.
for (const file of ['SKILL.md', 'assets/starter.asm', 'scripts/pack.mjs']) accessSync(resolve(skill, file));
const engine = resolve(skill, 'assets/engine');
const write = (path, text) => { mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, text); };
const copy = (source, target) => { mkdirSync(dirname(target), { recursive: true }); copyFileSync(resolve(root, source), target); };
const read = path => readFileSync(resolve(root, path), 'utf8');

for (const file of ['machine.wasm', 'build.json', 'app.js', 'style.css', 'machine-worker.js',
  'gpu-compiler.js', 'gpu-webgpu.js', 'audio-player.js', 'audio-worklet.js']) {
  copy(`web/${file}`, resolve(engine, 'web', file));
}
for (const file of ['wasm-host.mjs', 'png.mjs', 'validate-demo.mjs', 'serve.mjs']) {
  copy(`scripts/${file}`, resolve(engine, 'scripts', file));
}
for (const file of ['pack.mjs', 'codec.mjs', 'range.mjs', 'stub.mjs', 'linker.mjs', 'linker.wasm']) {
  copy(`tools/pack/${file}`, resolve(engine, 'tools/pack', file));
}
const wasm = readFileSync(resolve(engine, 'web/machine.wasm'));
const wasmHash = createHash('sha256').update(wasm).digest('hex');
if (JSON.parse(read('web/build.json')).sha256 !== wasmHash) throw new Error('Stale build.json; run npm run build');
if (WebAssembly.Module.imports(new WebAssembly.Module(wasm)).length) throw new Error('Engine must be import-free');
// Reuse the actual viewer with just the tiny starter; do not distribute the showcase demos.
const html = read('web/classic.html');
const select = /(<select id="example-select"[^>]*>)[\s\S]*?(<\/select>)/;
if (!select.test(html)) throw new Error('Viewer example selector changed; update skill packaging');
write(resolve(engine, 'web/index.html'), html.replace(select,
  '$1\n              <option value="examples/starter.asm">Minimal RGB starter</option>\n            $2')
  .replace('AURORA.ASM', 'STARTER.ASM'));
copy(resolve(skill, 'assets/starter.asm'), resolve(engine, 'web/examples/starter.asm'));

// Extract current author-facing contracts, leaving internal Rust/host integration seams out.
let cpu = read('docs/bootstrap-contract.md').split('## WASM ABI')[0];
cpu = cpu.replace(/^CPU API:.*\n/gm, '').replace(/^Video API:.*\n/gm, '');
cpu = cpu.replace(/Assembler API:.*?Support labels,/, 'Assembler: supports labels,');
cpu = cpu.replace(/This profile delivers[^\n]+/, 'CPU/video baseline shared by all profiles. `.profile bootstrap-1` selects version 1; `gpu-1` selects version 2; `spu-1` selects version 3; `dynamic-1` selects version 4. GPU completion also wakes WFI in versions 2/3/4. No DMA, general IRQ or timer peripheral is implemented.');
write(resolve(skill, 'references/machine.md'), cpu.trim() + '\n');
const gpu = read('spec/gpu-1.md').split('## Rust integration seam')[0];
write(resolve(skill, 'references/gpu.md'), gpu.trim() + '\n');
const spu = read('spec/spu-1.md').split('## Integration seam')[0].replace('(gpu-1.md)', '(gpu.md)');
write(resolve(skill, 'references/spu.md'), spu.trim() + '\n');
write(resolve(skill, 'references/dynamic.md'), read('spec/dynamic-1.md').trim() + '\n');

const packed = spawnSync(process.execPath, [resolve(skill, 'scripts/pack.mjs')], { cwd: skill, stdio: 'inherit' });
if (packed.status !== 0) throw new Error('Could not package refreshed agent kit');
console.log(`Refreshed ${skill}; engine SHA-256 ${wasmHash}`);
