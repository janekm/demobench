import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { createLinker } from '../tools/pack/linker.mjs';

const build = spawnSync('cargo', ['build', '--release', '-p', 'db-asm', '--example', 'image'], { encoding: 'utf8' });
assert.equal(build.status, 0, build.stderr);
const linker = createLinker();
const temp = mkdtempSync(join(tmpdir(), 'db32-linker-test-'));
try {
  const sources = ['rgb-study', 'aurora', 'ray-tracer', 'gpu-ray-tracer', 'signal-garden', 'neon-stadium', 'astra', 'pelican']
    .map(name => readFileSync(`examples/${name}.asm`, 'utf8'));
  sources.push('.profile dynamic-1\n.entry boot\n.equ neg, -1\n.org 0x2d000\nboot: li r1, kernel\njal r14, done\ndone: halt\nkernel: g.jmp end\nend: g.end\n' + '.word 0\n'.repeat(1500));
  for (const source of sources) {
    const path = join(temp, 'source.asm'), prefix = join(temp, 'image');
    writeFileSync(path, source);
    const native = spawnSync('target/release/examples/image', [path, prefix], { encoding: 'utf8' });
    assert.equal(native.status, 0, native.stderr);
    const image = linker.link(source);
    assert.deepEqual(image.bytes, readFileSync(`${prefix}.bin`));
    assert.equal(image.listing, readFileSync(`${prefix}.listing`, 'utf8'));
    const { bytes, listing, ...metadata } = image;
    assert.deepEqual(metadata, JSON.parse(readFileSync(`${prefix}.json`)));
  }
  assert.throws(() => linker.link('unknown'), /unknown/);
  assert.equal(linker.exports.db_image_len(), 0);
  assert.equal(linker.exports.db_metadata_len(), 0);
  assert.equal(linker.exports.db_listing_len(), 0);
  assert.throws(() => linker.link(';'.repeat(1048577)), /capacity/);
  assert.equal(linker.exports.db_link(1048577), -1);
  const e = linker.exports;
  new Uint8Array(e.memory.buffer, e.db_input_ptr(), 1)[0] = 255;
  assert.equal(e.db_link(1), -1);
  assert.equal(linker.link('halt').bytes.length, 4);
  console.log('PASS: portable WASM linker matches native images, metadata and listings; bounds and failure recovery.');
} finally { rmSync(temp, { recursive: true, force: true }); }
