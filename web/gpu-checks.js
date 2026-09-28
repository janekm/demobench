// Optional real-hardware checks. Run runGpuChecks() from this module in a
// secure browser context; the normal application never imports this file.
import { WebGpuBackend } from './gpu-webgpu.js';

export async function runGpuChecks() {
  const created = await WebGpuBackend.create();
  if (!created.backend) throw new Error(created.reason);
  const gpu = created.backend;
  const { instance } = await WebAssembly.instantiate(await (await fetch('./machine.wasm')).arrayBuffer(), {});
  const w = instance.exports;
  const results = [];
  const assert = (value, message) => { if (!value) throw new Error(message); };
  const assemble = source => {
    const bytes = new TextEncoder().encode(`.profile gpu-1\nhalt\n${source}`);
    const pointer = w.db_input_ptr();
    new Uint8Array(w.memory.buffer, pointer, bytes.length).set(bytes);
    if (w.db_assemble(bytes.length) !== 0) throw new Error(new TextDecoder().decode(new Uint8Array(w.memory.buffer, w.db_error_ptr(), w.db_error_len())));
    return new Uint8Array(w.memory.buffer, w.db_assembled_ptr() + 32, w.db_assembled_len() - 32).slice();
  };
  const dispatch = async (source, width, len, readRom = false) => {
    const rom = assemble(source);
    const bindings = [{ base: 0x10000, len, flags: 3 },
      readRom ? { base: 0, len: 4, flags: 1 } : { base: 0, len: 0, flags: 0 },
      { base: 0, len: 0, flags: 0 }, { base: 0, len: 0, flags: 0 }];
    return gpu.dispatch({ rom, codeBase: 4, codeLength: rom.length - 4, width, height: 1, bindings }, new Uint8Array(0x20000), new Uint32Array(16));
  };
  const test = async (name, fn) => { await fn(); results.push({ name, passed: true }); };
  try {
    await test('RGB888 adjacent-byte atomics and 65-invocation tail', async () => {
      const result = await dispatch('g.id g1, 2\ng.fli g2, 0.6\ng.fli g3, 0.3\ng.fli g4, 0.8\ng.rgb g2, g1, 0\ng.end', 65, 195);
      const bytes = result.writes[0].bytes;
      for (let i = 0; i < 65; i++) assert(bytes[i * 3] === 153 && bytes[i * 3 + 1] === 76 && bytes[i * 3 + 2] === 204, `Pixel ${i} corrupted`);
    });
    await test('Edited kernel changes hardware output', async () => {
      const result = await dispatch('g.fli g1, 0.2\ng.fli g2, 0.4\ng.fli g3, 0.6\ng.rgb g1, g0, 0\ng.end', 1, 3);
      assert(result.writes[0].bytes.join(',') === '51,102,153', 'Edited constants were not compiled');
    });
    await test('Divergent branches and immutable ROM loads', async () => {
      const source = 'g.id g1, 2\ng.bz g1, zero\ng.ld g2, g0, 1\ng.stb g2, g1, 0\ng.end\nzero: g.li g2, 73\ng.stb g2, g1, 0\ng.end';
      const result = await dispatch(source, 2, 2, true);
      assert(result.writes[0].bytes[0] === 73 && result.writes[0].bytes[1] === assemble(source)[0], 'Divergent load/store mismatch');
    });
    await test('Sphere intersection with non-unit ray', async () => {
      const result = await dispatch('g.fli g6, 2.0\ng.fli g9, 6.0\ng.fli g10, 2.0\ng.sphere g11, g1, g4, g7\ng.st g11, g0, 0\ng.end', 1, 4);
      const distance = new DataView(result.writes[0].bytes.buffer).getFloat32(0, true);
      assert(Math.abs(distance - 2) < 0.00001, `Sphere t=${distance}`);
    });
    await test('Out-of-bounds invocation discards dispatch output', async () => {
      let failed = false;
      try { await dispatch('g.id g1, 2\ng.li g2, 255\ng.stb g2, g1, 0\ng.end', 2, 1); }
      catch (error) { failed = /flag 1/.test(error.message); }
      assert(failed, 'Missing bounds failure');
    });
    await test('Infinite kernel terminates at hardware instruction limit', async () => {
      let failed = false;
      try { await dispatch('loop: g.jmp loop', 1, 4); }
      catch (error) { failed = /flag 2/.test(error.message); }
      assert(failed, 'Missing budget failure');
    });
    await test('SPU read/write state persists and observes earlier stores within an invocation', async () => {
      const rom = assemble('g.id g1, 2\ng.li g2, 4\ng.mul g1, g1, g2\ng.ld g3, g1, 0\ng.li g4, 1\ng.add g3, g3, g4\ng.st g3, g1, 0\ng.ld g3, g1, 0\ng.add g3, g3, g4\ng.st g3, g1, 0\ng.end');
      const ram = new Uint8Array(0x20000);
      const descriptor = {rom, codeBase:4, codeLength:rom.length-4, width:65, height:1,
        allowReadWrite:true, bindings:[{base:0x10000,len:65*4,flags:3}, ...Array.from({length:3},()=>({base:0,len:0,flags:0}))]};
      for(let block=1;block<=2;block++){
        const result=await gpu.dispatch(descriptor,ram,new Uint32Array(16));
        for(const write of result.writes)ram.set(write.bytes,write.offset);
        const state=new DataView(ram.buffer);
        for(let lane=0;lane<65;lane++)assert(state.getUint32(lane*4,true)===block*2,`State mismatch in lane ${lane}, block ${block}`);
      }
    });
    await test('SPU worker produces bounded finite stereo PCM on WebGPU', async () => {
      const source = await (await fetch(new URL('./examples/signal-garden.asm', import.meta.url))).text();
      const worker = new Worker(new URL('./machine-worker.js', import.meta.url), {type:'module'});
      let timer;
      try {
        await new Promise((resolve,reject)=>{
          let audioFrames=0,peak=0,hardware=false;
          timer=setTimeout(()=>reject(new Error('SPU hardware worker timed out')),10000);
          worker.onerror=event=>reject(new Error(event.message));
          worker.onmessage=({data})=>{
            if(data.type==='ready')worker.postMessage({type:'assemble',source});
            if(data.type==='error'||data.type==='init-error')reject(new Error(data.message));
            if(data.type==='audio'){
              if(data.rate!==48000||!(data.samples instanceof Float32Array)||data.samples.length%2)return reject(new Error('Invalid PCM transport'));
              for(const value of data.samples){if(!Number.isFinite(value)||Math.abs(value)>1)return reject(new Error('Invalid PCM sample'));peak=Math.max(peak,Math.abs(value));}
              audioFrames+=data.samples.length/2;
            }
            if(data.type==='state'&&data.audio?.backend==='webgpu')hardware=true;
            if(hardware&&audioFrames>=4800&&peak>.1)resolve();
          };
        });
      } finally {clearTimeout(timer);worker.terminate();}
    });
    await test('Invalid hardware PCM falls back before publishing the block', async () => {
      const source = await (await fetch(new URL('./examples/signal-garden.asm', import.meta.url))).text();
      const backendUrl = new URL('./gpu-webgpu.js', import.meta.url).href;
      const workerUrl = new URL('./machine-worker.js', import.meta.url).href;
      // Corrupt one hardware completion in a disposable test worker only.
      const blob = new Blob([`import {WebGpuBackend} from ${JSON.stringify(backendUrl)};
        const dispatch=WebGpuBackend.prototype.dispatch;
        WebGpuBackend.prototype.dispatch=async function(...args){
          const result=await dispatch.apply(this,args);
          if(args[0].allowReadWrite){
            const bytes=result.writes[0].bytes;
            new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength).setFloat32(0,NaN,true);
          }
          return result;
        };
        await import(${JSON.stringify(workerUrl)});`], {type:'text/javascript'});
      const url = URL.createObjectURL(blob), worker = new Worker(url,{type:'module'});
      let timer;
      try {
        await new Promise((resolve,reject)=>{
          timer=setTimeout(()=>reject(new Error('Invalid-PCM fallback timed out')),10000);
          worker.onerror=event=>reject(new Error(event.message));
          worker.onmessage=({data})=>{
            if(data.type==='ready')worker.postMessage({type:'assemble',source});
            if(data.type==='error'||data.type==='init-error')reject(new Error(data.message));
            if(data.type==='state'&&data.frameCount>=2){
              if(data.audio.backend==='wasm'&&/Nonfinite/.test(data.audio.reason)&&data.audio.peak>0&&data.audio.samples>0)resolve();
              else reject(new Error('Invalid hardware PCM did not fall back to the reference'));
            }
          };
        });
      } finally {clearTimeout(timer);worker.terminate();URL.revokeObjectURL(url);}
    });
    await test('Browser without WebGPU runs both GPU and SPU cartridges in WASM', async () => {
      for (const demo of ['gpu-ray-tracer', 'signal-garden']) {
      const source = await (await fetch(new URL(`./examples/${demo}.asm`, import.meta.url))).text();
      const workerUrl = new URL('./machine-worker.js', import.meta.url).href;
      const blob = new Blob([`Object.defineProperty(self.navigator, 'gpu', {value: undefined}); await import(${JSON.stringify(workerUrl)});`], { type: 'text/javascript' });
      const url = URL.createObjectURL(blob);
      const worker = new Worker(url, { type: 'module' });
      let timer;
      try {
        await new Promise((resolve, reject) => {
          timer = setTimeout(() => reject(new Error('Unavailable-GPU fallback worker timed out')), 5000);
          worker.onerror = event => reject(new Error(event.message));
          worker.onmessage = ({ data }) => {
            if (data.type === 'ready') worker.postMessage({ type: 'assemble', source });
            if (data.type === 'error' || data.type === 'init-error') reject(new Error(data.message));
            if (data.type === 'state' && data.frameCount >= 2) {
              if (data.backend.active === 'wasm' && !data.backend.available && data.backend.reason &&
                (demo !== 'signal-garden' || (data.audio.backend === 'wasm' && data.audio.samples > 0 && data.audio.peak > 0))) resolve();
              else reject(new Error('Unavailable WebGPU was not labelled as WASM fallback'));
            }
          };
        });
      } finally { clearTimeout(timer); worker.terminate(); URL.revokeObjectURL(url); }
      }
    });
    await test('RAM kernel edits invalidate cached pipelines at the same address', async () => {
      const rom = assemble('g.li g1, 17\ng.st g1,g0,0\ng.end');
      const ram = new Uint8Array(131072), codeBase = 0x2c000;
      ram.set(rom.subarray(4), codeBase - 0x10000);
      const descriptor = { rom, ram, allowRamCode: true, codeBase, codeLength: rom.length - 4, width: 1, height: 1,
        bindings: [{ base: 0x10000, len: 4, flags: 3 }, ...Array.from({ length: 3 }, () => ({ base: 0, len: 0, flags: 0 }))] };
      const first = await gpu.dispatch(descriptor, ram, new Uint32Array(16));
      new DataView(ram.buffer).setUint32(codeBase - 0x10000 + 4, 29, true);
      const second = await gpu.dispatch(descriptor, ram, new Uint32Array(16));
      assert(new DataView(first.writes[0].bytes.buffer).getUint32(0, true) === 17, 'First RAM literal was not executed');
      assert(new DataView(second.writes[0].bytes.buffer).getUint32(0, true) === 29, 'RAM code edit reused stale shader');
    });
    await test('Lost device is rejected before another dispatch', async () => {
      gpu.device.destroy();
      await gpu.device.lost;
      let failed = false;
      try { await dispatch('g.end', 1, 4); }
      catch (error) { failed = /device lost/i.test(error.message); }
      assert(failed, 'Lost device was reused');
    });
    return { backend: 'webgpu', tests: results, passed: results.length };
  } finally { gpu.device.destroy(); }
}
