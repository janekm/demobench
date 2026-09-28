import assert from 'node:assert/strict';
import { StereoPcmQueue } from '../web/audio-worklet.js';

const tests=[];
const test=(name,fn)=>tests.push([name,fn]);
function queue(rate=48000,capacity=7200,prebuffer=768){
  const q=new StereoPcmQueue(rate,capacity,prebuffer);q.reset(1);q.setActive(true);return q;
}
function render(q,count){const l=new Float32Array(count),r=new Float32Array(count);q.render(l,r);return [l,r];}
const ramp=count=>Float32Array.from({length:count*2},(_,i)=>(i&1)?-Math.floor(i/2)/1000:Math.floor(i/2)/1000);

test('PCM transport preserves stereo, prebuffers, and wraps its bounded ring',()=>{
  const q=queue(48000,16,4);
  assert.ok(q.enqueue(ramp(3),1));assert.ok(render(q,2)[0].every(x=>x===0));
  q.enqueue(ramp(9),1);const [l,r]=render(q,10);
  assert.equal(l[2],Math.fround(.002));assert.equal(r[5],Math.fround(-.002));
  q.enqueue(ramp(10),1);assert.equal(q.queuedFrames,12);
  const [wrapped]=render(q,12);assert.equal(wrapped[0],Math.fround(.007));
  assert.equal(wrapped[11],Math.fround(.009));assert.equal(q.queuedFrames,0);
});
test('48 kHz PCM resamples to 44.1 and 96 kHz at the correct rate',()=>{
  for(const rate of [44100,96000]){
    const q=queue(rate);q.enqueue(ramp(2400),1);
    const count=rate/100;const [l,r]=render(q,count);
    for(let i=0;i<count;i++){
      assert.ok(Math.abs(l[i]-i*48000/rate/1000)<1e-6);
      assert.ok(Math.abs(l[i]+r[i])<1e-6);
    }
    assert.ok(Math.abs(q.queuedFrames-(2400-480))<=1);
    assert.equal(q.underruns,0);
  }
});
test('Epoch changes and pause discard old PCM without mixing timelines',()=>{
  const q=queue(48000,32,4);q.enqueue(ramp(8),1);
  q.reset(2);assert.equal(q.queuedFrames,0);assert.equal(q.enqueue(ramp(8),1),false);
  q.enqueue(ramp(8),2);q.setActive(false);assert.ok(render(q,8)[0].every(x=>x===0));
  assert.equal(q.queuedFrames,0);q.setActive(true);q.enqueue(ramp(8),2);
  assert.equal(render(q,8)[0][7],Math.fround(.007));
});
test('Overflow is bounded and underruns rebuffer instead of replaying stale data',()=>{
  const q=queue(48000,16,4);q.enqueue(ramp(12),1);
  assert.equal(q.enqueue(ramp(8),1),false);assert.equal(q.droppedFrames,8);
  render(q,20);assert.equal(q.underruns,1);assert.equal(q.queuedFrames,0);
  q.enqueue(ramp(2),1);assert.ok(render(q,8)[0].every(x=>x===0));
  q.enqueue(ramp(2),1);assert.equal(render(q,4)[0][1],Math.fround(.001));
});
test('Malformed transport buffers are rejected and nonfinite samples become silence',()=>{
  const q=queue(48000,16,2);
  assert.equal(q.enqueue(new Uint8Array(4),1),false);
  assert.equal(q.enqueue(new Float32Array(3),1),false);
  q.enqueue(new Float32Array([NaN,Infinity,.25,-.25]),1);
  const [l,r]=render(q,2);assert.deepEqual([...l],[0,.25]);assert.deepEqual([...r],[0,-.25]);
});
for(const [name,fn] of tests){fn();console.log(`PASS ${name}`);}
console.log(`${tests.length} PCM transport tests passed`);
