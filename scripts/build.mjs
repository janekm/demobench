import { spawnSync } from 'node:child_process';
import { mkdirSync, copyFileSync, readdirSync, writeFileSync, readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
const root = fileURLToPath(new URL('../', import.meta.url));
const result = spawnSync('cargo', ['build', '--release', '--target', 'wasm32-unknown-unknown', '-p', 'db-wasm', '-p', 'db-linker'], {
  cwd: root, stdio: 'inherit', env: { ...process.env,
    RUSTFLAGS: '-C link-arg=--max-memory=16777216 -C link-arg=-zstack-size=1048576' },
});
if (result.status !== 0) process.exit(result.status ?? 1);
mkdirSync(resolve(root, 'web/examples'), { recursive: true });
copyFileSync(resolve(root, 'target/wasm32-unknown-unknown/release/db_wasm.wasm'), resolve(root, 'web/machine.wasm'));
const linker = readFileSync(resolve(root, 'target/wasm32-unknown-unknown/release/db_linker.wasm'));
if (WebAssembly.Module.imports(new WebAssembly.Module(linker)).length) throw new Error('Linker must be import-free');
writeFileSync(resolve(root, 'tools/pack/linker.wasm'), linker);
for (const file of readdirSync(resolve(root, 'examples')).filter(f => f.endsWith('.asm'))) {
  copyFileSync(resolve(root, 'examples', file), resolve(root, 'web/examples', file));
}
const wasm = readFileSync(resolve(root, 'web/machine.wasm'));
const module = new WebAssembly.Module(wasm);
const imports = WebAssembly.Module.imports(module);
if (imports.length) throw new Error(`Unexpected WASM imports: ${JSON.stringify(imports)}`);
const hash = createHash('sha256').update(wasm).digest('hex');
writeFileSync(resolve(root, 'web/build.json'), JSON.stringify({ supportedProfiles: ['bootstrap-1', 'gpu-1', 'spu-1', 'dynamic-1'], abi: 1, wasmBytes: wasm.length, sha256: hash }, null, 2) + '\n');
console.log(`Built import-free machine.wasm (${wasm.length} bytes) SHA-256 ${hash}`);
