import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createMachine, FRAME_TICKS } from './wasm-host.mjs';
const tests=[];
const test=(name,fn)=>tests.push([name,fn]);
const config=(format,stride)=>`li r1, 0xf5000\nli r2, 0x10000\nsw r2, 0(r1)\nli r2, ${stride}\nsw r2, 4(r1)\nli r2, ${format}\nsw r2, 8(r1)\nli r2, 0x28000\nsw r2, 12(r1)\naddi r2, r0, 1\nsw r2, 16(r1)\nsw r2, 20(r1)\nhalt`;

test('WASM assembly and CPU produce exact pixels in every video format',()=>{
  for(const [format,stride,byte] of [[0,20,128],[1,40,64],[2,80,16],[3,160,1],[4,480,17]]){
    const m=createMachine();
    const code=`li r1, 0x10000\naddi r2, r0, ${byte}\nsb r2, 0(r1)\n${format===4?'addi r2, r0, 34\nsb r2, 1(r1)\naddi r2, r0, 51\nsb r2, 2(r1)':'li r1, 0x28003\naddi r2, r0, 17\nsb r2, 0(r1)\naddi r2, r0, 34\nsb r2, 1(r1)\naddi r2, r0, 51\nsb r2, 2(r1)'}\n${config(format,stride)}`;
    m.load(m.assemble(code));m.runFrames(2);
    assert.equal(m.info().format,format);
    assert.deepEqual([...m.frame().slice(0,8)],[17,34,51,255,0,0,0,255]);
  }
});
test('ROM is read-only and absent peripherals fault',()=>{
  for(const code of ['sw r0, 0(r0)','li r1, 0xf3000\nlw r2, 0(r1)','li r1, 0xf6000\nsw r0, 0(r1)']){
    const m=createMachine();m.load(m.assemble(code));assert.throws(()=>m.run(100),/unmapped|read-only/);
  }
});
test('Misaligned and truncated accesses fault',()=>{
  const m=createMachine();m.load(m.assemble('li r1, 0x10001\nlw r2, 0(r1)'));assert.throws(()=>m.run(10),/align/i);
  const cart=m.assemble('halt');assert.throws(()=>m.load(cart.slice(0,-1)),/length/);
  cart[16]=1;assert.throws(()=>m.load(cart),/reserved/);
});
test('Failed builds clear previous cartridge and oversize builds are rejected',()=>{
  const m=createMachine();m.assemble('halt');assert.throws(()=>m.assemble('wrong_opcode r1'),/unknown/i);
  assert.equal(m.exports.db_assembled_len(),0);
  assert.throws(()=>m.assemble('nop\n'.repeat(1025)),/4096|large|limit|size/i);
});
test('WASM has bounded memory and run slices',()=>{
  const m=createMachine();m.load(m.assemble('loop: j loop'));
  assert.throws(()=>m.run(FRAME_TICKS*10+1),/slice/);
  assert.throws(()=>m.exports.memory.grow(257),RangeError);
});
test('Malformed assembler expressions report errors without trapping WASM',()=>{
  const m=createMachine();
  for(const source of [
    '.equ MIN, -9223372036854775807-1\nhalt\n.word -MIN',
    '.equ MIN, -9223372036854775807-1\nbeq r0,r0,MIN',
    '.equ UNUSED, missing_symbol\nhalt',
    '.equ A, B\n.equ B, A\nhalt',
    '.entry 4294967296\nhalt',
  ]){
    assert.throws(()=>m.assemble(source),error=>!(error instanceof WebAssembly.RuntimeError));
    m.load(m.assemble('halt'));m.run(1);assert.equal(m.info().status,2);
  }
});
test('Slicing preserves unfinished instruction effects',()=>{
  const source='li r1, 0x10000\naddi r2, r0, 3\nloop: mul r2, r2, r2\nsw r2, 0(r1)\naddi r2, r2, 1\nj loop';
  const a=createMachine(),b=createMachine();a.load(a.assemble(source));b.load(b.assemble(source));
  a.run(10000);for(let i=0;i<10000;i++)b.run(1);
  assert.equal(a.info().pc,b.info().pc);for(let i=0;i<16;i++)assert.equal(a.exports.db_register(i),b.exports.db_register(i));
  assert.equal(a.info().ticks,b.info().ticks);
});
test('Example cartridges fit 4 KiB and generate repeatable nonblank images',()=>{
  for(const name of ['aurora','rgb-study','ray-tracer']){
    const source=readFileSync(new URL(`../examples/${name}.asm`,import.meta.url),'utf8');
    const a=createMachine(),b=createMachine();const cart=a.assemble(source);assert.ok(cart.length<=4128);
    const frames=name==='ray-tracer'?480:120;
    a.load(cart);b.load(cart);a.runFrames(frames);b.runFrames(frames);
    assert.equal(a.info().rgbaSha256,b.info().rgbaSha256);
    if(name==='ray-tracer')assert.equal(a.info().status,2,'ray tracer must finish within 480 frames');
    const colors=new Set();const bytes=a.frame();for(let i=0;i<bytes.length;i+=4)colors.add(`${bytes[i]},${bytes[i+1]},${bytes[i+2]}`);
    assert.ok(colors.size>16,`${name} has only ${colors.size} colors`);
    console.log(`  ${name}: ${cart.length-32} payload bytes, ${colors.size} colours, ${a.info().rgbaSha256.slice(0,16)}`);
  }
});
const raySource=readFileSync(new URL('../examples/ray-tracer.asm',import.meta.url),'utf8');
// Run the real guest routines with analytic, axis-aligned geometry fixtures.
test('Ray intersections choose the nearest surface and respect a finite light distance',()=>{
  for(const [origin,direction,limit,expected,distance] of [
    [[0,-80,0],[0,0,1024],400,'spheres+48',368],
    [[0,-80,0],[0,0,1024],350,'0',350], // sphere lies beyond the light
    [[0,-80,0],[0,0,1024],368,'0',368], // shadow segment excludes its endpoint
    [[0,0,0],[0,-1024,0],200,'1',144], // floor at -9 in Q4
    [[0,0,0],[0,1024,0],200,'0',200], // upward ray misses the floor
  ]){
    const fixture=[...origin,...direction].map((value,i)=>`li r1, ${value}\nsw r1, ${i*4}(r15)`).join('\n');
    const source=raySource.replace('.entry start','.entry probe')+`\nprobe:\nli r15, SCRATCH\n${fixture}\nsw r0, 44(r15)\nli r1, ${limit}\nsw r1, 40(r15)\njal r14, trace\nlw r1, 36(r15)\nlw r2, 40(r15)\nli r3, ${expected}\nhalt\n`;
    const m=createMachine();m.load(m.assemble(source));m.run(20000);
    assert.equal(m.info().status,2);
    assert.equal(m.exports.db_register(1),m.exports.db_register(3));
    assert.equal(m.exports.db_register(2),distance);
  }
});
// Limit only the camera raster loop: shading, geometry and bounce code are unchanged.
function rayPixel(source,x,y){
  source=source.replace('sw r0, 56(r15)',`li r1, ${y}\nsw r1, 56(r15)`)
    .replace('sw r0, 52(r15)',`li r1, ${x}\nsw r1, 52(r15)`)
    .replace('addi r7, r7, 3','halt');
  const m=createMachine();m.load(m.assemble(source));m.runFrames(2);
  assert.equal(m.info().status,2);
  return [...m.frame().slice(0,3)];
}
test('Sphere reflections respond to another sphere material and sphere shadows block light',()=>{
  // This camera ray hits the copper sphere, then reflects into the teal sphere.
  const twoHits=raySource.replace('.equ MAX_HITS, 3','.equ MAX_HITS, 2');
  const red=rayPixel(twoHits.replace('0x48dec5','0xff0000'),100,47);
  const blue=rayPixel(twoHits.replace('0x48dec5','0x0000ff'),100,47);
  assert.ok(red[0]>blue[0]+10,`reflected red material: ${red} versus ${blue}`);
  assert.ok(blue[2]>red[2]+10,`reflected blue material: ${blue} versus ${red}`);
  // Isolate direct illumination: the left sphere blocks the point light here.
  const direct=raySource.replace('.equ MAX_HITS, 3','.equ MAX_HITS, 1');
  const noShadow=direct.replace('.equ SHADOWS, 1','.equ SHADOWS, 0');
  const shadow=rayPixel(direct,98,38),lit=rayPixel(noShadow,98,38);
  assert.ok(lit.reduce((a,b)=>a+b,0)>shadow.reduce((a,b)=>a+b,0)+120);
  assert.deepEqual(rayPixel(direct,40,32),rayPixel(noShadow,40,32),'unoccluded surface is unaffected');
});
function gpuSource(kernel,{width=1,bytes=3}={}){
  return `.profile gpu-1
li r1, 0xf3000
li r2, kernel
sw r2, 0(r1)
li r2, kernel_end-kernel
sw r2, 4(r1)
li r2, ${width}
sw r2, 8(r1)
li r2, 1
sw r2, 12(r1)
li r2, 0x10000
sw r2, 64(r1)
li r2, ${bytes}
sw r2, 68(r1)
li r2, 3
sw r2, 72(r1)
li r2, 1
sw r2, 16(r1)
${config(4,480)}
kernel:
${kernel}
kernel_end:
`;
}
test('GPU WASM dispatch writes RGB888, masks tail lanes, and runs after CPU HALT',()=>{
  const m=createMachine();
  m.load(m.assemble(gpuSource('g.fli g1, 1.0\ng.fli g2, 0.5\ng.mov g3, g0\ng.id g4, 2\ng.rgb g1, g4, 0\ng.end',{width:65,bytes:195})));
  m.runFrames(2);
  assert.equal(m.info().profile,'gpu-1');
  assert.equal(m.info().status,2);
  assert.equal(m.info().gpu.dispatches,1);
  assert.equal(m.info().gpu.invocations,65);
  for(let i=0;i<65;i++)assert.deepEqual([...m.frame().slice(i*4,i*4+4)],[255,127,0,255]);
  assert.deepEqual([...m.frame().slice(65*4,65*4+4)],[0,0,0,255]);
});
test('GPU faults are bounded guest errors, not WASM traps or partial lane stores',()=>{
  for(const kernel of [
    'g.li g1, 3\ng.stb g0, g1, 0\ng.end',
    'g.fli g1, 1.0\ng.fdiv g2, g1, g0\ng.end',
    'g.li g1, 0x7fc00000\ng.sqrt g2, g1\ng.end',
    'loop: g.jmp loop',
  ]){
    const m=createMachine();m.load(m.assemble(gpuSource(kernel)));
    assert.throws(()=>m.run(FRAME_TICKS*6),error=>!(error instanceof WebAssembly.RuntimeError)&&/GPU_/.test(error.message));
    assert.equal(m.info().gpu.status,'fault');
  }
  const m=createMachine();m.load(m.assemble(gpuSource('g.id g1, 2\ng.li g2, 255\ng.stb g2, g1, 0\ng.end',{width:2,bytes:1})));
  assert.throws(()=>m.runFrames(2),/lane 1/);
  assert.deepEqual([...m.frame().slice(0,4)],[0,0,0,255]);
});
test('GPU sphere instruction returns the distance for a non-unit ray',()=>{
  const kernel='g.mov g1, g0\ng.mov g2, g0\ng.mov g3, g0\ng.mov g4, g0\ng.mov g5, g0\ng.fli g6, 2.0\ng.mov g7, g0\ng.mov g8, g0\ng.fli g9, 6.0\ng.fli g10, 2.0\ng.sphere g11, g1, g4, g7\ng.st g11, g0, 0\ng.end';
  const m=createMachine();m.load(m.assemble(gpuSource(kernel,{bytes:4})));m.runFrames(2);
  // (6-2)/2 = 2.0 -> little-endian float bytes 00 00 00 40.
  assert.deepEqual([...m.frame().slice(0,8)],[0,0,0,255,64,0,0,255]);
});
test('GPU ray tracer animates with repeatable output within the virtual frame budget',()=>{
  const source=readFileSync(new URL('../examples/gpu-ray-tracer.asm',import.meta.url),'utf8');
  for(const shift of [0,1]){
    const selected=source.replace(/\.equ PIXEL_SHIFT,\s*[01]/,`.equ PIXEL_SHIFT, ${shift}`);
    const a=createMachine(),b=createMachine();const cart=a.assemble(selected);
    assert.ok(cart.length<=4128);a.load(cart);b.load(cart);
    a.runFrames(8);b.runFrames(8);
    assert.equal(a.info().rgbaSha256,b.info().rgbaSha256);
    assert.ok(a.info().gpu.dispatches>=6);
    assert.ok(a.info().gpu.lastTicks>0&&a.info().gpu.lastTicks<=FRAME_TICKS);
    const first=a.info().rgbaSha256, pixels=a.frame();
    a.runFrames(8);
    assert.notEqual(a.info().rgbaSha256,first,'moving light changes presented pixels');
    if(shift===1){
      for(let y=0;y<120;y+=2)for(let x=0;x<160;x+=2){
        const p=(y*160+x)*4, base=[...pixels.slice(p,p+4)];
        for(const offset of [4,640,644])assert.deepEqual([...pixels.slice(p+offset,p+offset+4)],base,'2x2 pixels are written by the same ray');
      }
    }
  }
});
test('SPU PCM is deterministic across host slices and drains independently of its timeline',()=>{
  const source=readFileSync(new URL('../examples/signal-garden.asm',import.meta.url),'utf8');
  const a=createMachine(),b=createMachine();const cart=a.assemble(source);
  assert.ok(cart.length<=4128);a.load(cart);b.load(cart);
  assert.equal(a.info().profile,'spu-1');
  let frames=0, peak=0, stereo=0;
  for(let frame=0;frame<120;frame++){
    a.runFrames(1);b.run(FRAME_TICKS/2);b.run(FRAME_TICKS/2);
    const pcm=a.audio();assert.deepEqual(pcm,b.audio());
    assert.equal(a.audio().length,0,'draining must empty the queue');
    for(let i=0;i<pcm.length;i+=2){
      assert.ok(Number.isFinite(pcm[i])&&Number.isFinite(pcm[i+1]));
      peak=Math.max(peak,Math.abs(pcm[i]),Math.abs(pcm[i+1]));
      stereo+=Math.abs(pcm[i]-pcm[i+1]);
    }
    frames+=pcm.length/2;
  }
  assert.equal(frames,96000);assert.equal(a.info().audio.samples,frames);
  assert.equal(a.info().audio.overruns,0);assert.ok(peak>0.1&&peak<=1);assert.ok(stereo>100);
  assert.equal(a.info().rgbaSha256,b.info().rgbaSha256);
});
test('Disabled SPU emits clocked silence and bounds a neglected host queue',()=>{
  const m=createMachine();m.load(m.assemble('.profile spu-1\nhalt'));
  m.runFrames(16);
  assert.equal(m.info().audio.samples,12800);
  assert.equal(m.info().audio.overruns,12800-8192);
  const pcm=m.audio();assert.equal(pcm.length,8192*2);assert.ok(pcm.every(x=>x===0));
  m.runFrames(1);assert.ok(m.audio().length>0);
});
let failures=0;
for(const [name,fn] of tests){try{fn();console.log(`PASS ${name}`);}catch(error){failures++;console.error(`FAIL ${name}\n${error.stack}`);}}
if(failures)process.exitCode=1;else console.log(`${tests.length} WASM integration tests passed`);
