import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { packSource } from './pack.mjs';
mkdirSync('web/pack-fixtures', { recursive: true });
const dynamic = packSource(readFileSync('examples/dynamic-kernel.asm', 'utf8'), { load: 0x2d000 });
writeFileSync('web/pack-fixtures/dynamic.packed.asm', dynamic.packedSource);
writeFileSync('web/pack-fixtures/astra.packed.asm', readFileSync('artifacts/pack/benchmark/astra.packed.asm'));
console.log('Prepared local-only packed browser fixtures');
