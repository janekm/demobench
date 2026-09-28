// Measure the reference WASM engine, separately from the virtual GPU budget.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { performance } from 'node:perf_hooks';
import { cpus, platform, arch } from 'node:os';
import { createMachine, FRAME_TICKS } from './wasm-host.mjs';
const args=process.argv.slice(2);
const option=(name,fallback)=>{const at=args.indexOf(name);return at<0?fallback:args[at+1];};
const frames=Number(option('--frames','60')),warmup=Number(option('--warmup','8'));
if(!Number.isInteger(frames)||frames<2||frames>600||!Number.isInteger(warmup)||warmup<0||warmup>120)throw new Error('frames must be 2..600; warmup 0..120');
let source=readFileSync('examples/gpu-ray-tracer.asm','utf8');
const shift=option('--pixel-shift',null);
if(shift!==null){
  if(!['0','1'].includes(shift))throw new Error('pixel-shift must be 0 or 1');
  if(!source.includes('.equ PIXEL_SHIFT,'))throw new Error('kernel does not expose PIXEL_SHIFT');
  source=source.replace(/\.equ PIXEL_SHIFT,\s*[01]/,`.equ PIXEL_SHIFT, ${shift}`);
}
const machine=createMachine(),cart=machine.assemble(source);
machine.load(cart);machine.runFrames(warmup);
const initial=machine.info(),durations=[],hashes=new Set();
// Hash/readback is outside the measured machine.run interval.
let runMs=0;
for(let i=0;i<frames;i++){
  const started=performance.now();machine.run(FRAME_TICKS);runMs+=performance.now()-started;
  const info=machine.info();durations.push(info.gpu.lastTicks);hashes.add(info.rgbaSha256);
}
const final=machine.info(), completed=final.gpu.dispatches-initial.gpu.dispatches;
const report={profile:final.profile,moduleSha256:final.wasmSha256,payloadBytes:cart.length-32,
  source:'examples/gpu-ray-tracer.asm',pixelShift:Number(source.match(/\.equ PIXEL_SHIFT,\s*([01])/)?.[1]??0),
  host:{node:process.version,platform:platform(),arch:arch(),cpu:cpus()[0]?.model},
  warmupVirtualFrames:warmup,measuredVirtualFrames:frames,completedDispatches:completed,
  virtualTicksPerFrame:FRAME_TICKS,gpuTicks:{min:Math.min(...durations),max:Math.max(...durations)},
  virtualFrameBudgetMet:durations.every(t=>t>0&&t<=FRAME_TICKS),distinctPresentedFrames:hashes.size,
  referenceRunMs:runMs,referenceVirtualFramesPerSecond:frames*1000/runMs,
  referenceDispatchesPerSecond:completed*1000/runMs,
  host60HzMet:completed*1000/runMs>=60,
  scope:'Node WASM execution only; excludes UI presentation, serialization, hashing, startup and assembly'};
mkdirSync('artifacts',{recursive:true});
const path=option('--out','artifacts/gpu-benchmark.json');
writeFileSync(path,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({...report,report:path},null,2));
