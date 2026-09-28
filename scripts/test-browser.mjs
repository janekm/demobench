import assert from 'node:assert/strict';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createMachine, FRAME_TICKS } from './wasm-host.mjs';
// Optional browser QA dependency; runtime and standard tests require no npm packages.
const { chromium, webkit } = await import(process.env.DEMO_BENCH_PLAYWRIGHT_MODULE || 'playwright');
const name=process.argv.includes('--webkit')?'webkit':'chromium';
const browser=await ({chromium,webkit}[name]).launch({headless:true,...(process.env.DEMO_BENCH_BROWSER_EXECUTABLE?{executablePath:process.env.DEMO_BENCH_BROWSER_EXECUTABLE}:{})});
const page=await browser.newPage({viewport:{width:1440,height:1100}});
const errors=[];page.on('pageerror',e=>errors.push(e.message));
const records=[];
mkdirSync('artifacts',{recursive:true});
try {
  await page.goto(process.env.DEMO_BENCH_URL || 'http://127.0.0.1:4173/studio.html');
  const cases=[['aurora',null],['gpu-ray-tracer','0'],['ray-tracer',null],['gpu-ray-tracer','1'],['rgb-study',null]];
  for(const [index,[demo,quality]] of cases.entries()){
    await page.locator('#example-select').selectOption(`examples/${demo}.asm`);
    const preview=createMachine();
    let selectedSource=readFileSync(`examples/${demo}.asm`,'utf8');
    const expected=preview.assemble(selectedSource).length-32;
    await page.waitForFunction(({expected,ray})=>window.__demoBench?.payloadSize===expected&&window.__demoBench?.frameCount>=8&&(!ray||window.__demoBench.status==='halted'),{expected,ray:demo==='ray-tracer'},{timeout:15000});
    if(quality!==null){
      // These are canonical pixel-parity checks. Acceleration deliberately uses
      // native GPU arithmetic and is covered separately by gpu-checks.js.
      await page.locator('#renderer-select').selectOption('wasm');
      await page.waitForFunction(()=>window.__demoBench?.backend?.requested==='wasm'&&window.__demoBench.frameCount>=8);
      await page.locator('#quality-select').selectOption(quality);
      await page.waitForFunction((fast)=>window.__demoBench?.gpu?.dispatches>=6&&window.__demoBench.gpu.lastTicks>0&&(window.__demoBench.gpu.lastTicks<100000)===fast,quality==='1',{timeout:15000});
      selectedSource=selectedSource.replace(/\.equ PIXEL_SHIFT,\s*[01]/,`.equ PIXEL_SHIFT, ${quality}`);
      assert.equal(await page.locator('#source').inputValue(),selectedSource,'quality selector edits visible source only');
    }
    if(demo==='ray-tracer'){
      const completed=await page.evaluate(()=>window.__demoBench.frameCount);
      await page.waitForFunction((frame)=>window.__demoBench.frameCount>frame,completed);
    }
    if(await page.evaluate(()=>window.__demoBench.playing))await page.locator('#play-button').click();
    await page.waitForFunction(()=>!window.__demoBench.playing);
    const state=await page.evaluate(()=>window.__demoBench);
    const canvasHash=await page.evaluate(async()=>{
      const pixels=document.querySelector('#screen').getContext('2d').getImageData(0,0,160,120).data;
      return [...new Uint8Array(await crypto.subtle.digest('SHA-256',pixels))].map(x=>x.toString(16).padStart(2,'0')).join('');
    });
    const headless=createMachine();headless.load(headless.assemble(selectedSource));headless.runFrames(state.frameCount);
    assert.equal(state.wasmSha256,headless.wasmHash,'browser and headless module identity');
    assert.equal(Number(state.tick),state.frameCount*FRAME_TICKS);
    assert.equal(canvasHash,headless.info().rgbaSha256,`${demo} browser vs headless RGBA`);
    const before=state.frameCount;await page.locator('#step-button').click();
    await page.waitForFunction((n)=>window.__demoBench.frameCount===n+1,before);
    await page.screenshot({path:`artifacts/${name}-${demo}${quality===null?'':`-${quality}`}-viewer.png`,fullPage:true});
    records.push({browser:name,demo,quality,frames:state.frameCount,wasmSha256:state.wasmSha256,rgbaSha256:canvasHash,payload:state.payloadSize,gpu:state.gpu,parity:true});
  }
  // Actual controls: assembly errors, old-cartridge reset, edit/rebuild, downloads.
  const source=await page.locator('#source').inputValue();
  await page.locator('#source').fill('not_an_opcode r1');await page.locator('#assemble-button').click();
  await page.waitForFunction(()=>document.querySelector('#message').classList.contains('error'));
  assert.match(await page.locator('#message').textContent(),/line|unknown/i);
  await page.locator('#reset-button').click();await page.waitForFunction(()=>window.__demoBench.frameCount===0);
  await page.locator('#step-button').click();await page.waitForFunction(()=>window.__demoBench.frameCount===1);
  await page.locator('#source').fill(source);await page.locator('#assemble-button').click();
  await page.waitForFunction(()=>window.__demoBench.frameCount>=8&&window.__demoBench.playing);
  await page.locator('#play-button').click();await page.waitForFunction(()=>!window.__demoBench.playing);
  const cartDownload=page.waitForEvent('download');await page.locator('#cartridge-button').click();
  const cart=await cartDownload;await cart.saveAs(`artifacts/${name}-download.db32`);
  assert.equal(readFileSync(`artifacts/${name}-download.db32`).length,468);
  const pngDownload=page.waitForEvent('download');await page.locator('#png-button').click();
  const image=await pngDownload;await image.saveAs(`artifacts/${name}-download.png`);
  assert.equal(readFileSync(`artifacts/${name}-download.png`).subarray(1,4).toString(),'PNG');
  await page.setViewportSize({width:390,height:844});
  assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'mobile horizontal overflow');
  await page.screenshot({path:`artifacts/${name}-mobile.png`,fullPage:true});
  assert.deepEqual(errors,[]);
  const report={records,controls:'pause, frame step, reset after failed build, edit/rebuild, PNG/cartridge export',mobileWidth:390,pageErrors:errors};
  writeFileSync(`artifacts/browser-${name}.json`,JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report,null,2));
} finally {await browser.close();}
