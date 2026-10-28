import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {VideoRecorder,VIDEO,checkVideo} from '../video.mjs';
import {newProject,makeAsset,exportArchive,importArchive,verifyAssets,validateProject} from '../core.mjs';
import {serializeProject,deserializeProject} from '../store.mjs';
const mp4 = await readFile(new URL('./fixtures/synthetic-rgbd.mp4',import.meta.url));
const clip = () => new Blob([mp4],{type:'video/mp4'});
async function project() { const p=newProject('Video');p.videos.push(await makeAsset(clip(),'test.mp4',{width:16,height:8,duration:1}));return p; }
class Track extends EventTarget { readyState='live'; }
function stream(audio=false) {const track=new Track();return{track,getVideoTracks:()=>[track],getAudioTracks:()=>audio?[{}]:[]};}
class FakeRecorder {
  static isTypeSupported = type => type === 'video/mp4';
  constructor(stream, options) { this.stream=stream;this.options=options;this.mimeType=options.mimeType;this.state='inactive';FakeRecorder.last=this; }
  start(interval) {this.interval=interval;this.state='recording';}
  stop() {this.state='inactive';queueMicrotask(()=>{this.ondataavailable({data:clip()});this.onstop();});}
}
test('video archive v3 and binary storage codec preserve exact clip bytes and metadata',async()=>{
  const p=await project(),raw=JSON.parse(await (await exportArchive(p)).text());assert.equal(raw.version,3);
  const copy=await importArchive(JSON.stringify(raw));assert.notEqual(copy.id,p.id);assert.equal(copy.videos[0].sha256,p.videos[0].sha256);assert.equal(copy.videos[0].duration,1);
  const stored=deserializeProject(structuredClone(await serializeProject(copy)));await verifyAssets(stored);
  assert.deepEqual(new Uint8Array(await stored.videos[0].blob.arrayBuffer()),new Uint8Array(mp4));
});
test('old v2 projects without videos remain unchanged and export v2',async()=>{
  const p=newProject('Previous');delete p.videos;validateProject(p);const raw=JSON.parse(await (await exportArchive(p)).text());assert.equal(raw.version,2);assert.equal(raw.project.videos,undefined);
  const copy=await importArchive(JSON.stringify(raw));assert.deepEqual(copy.videos,[]);assert.equal(p.videos,undefined);
});
test('video hashes, container identity, dimensions, duration and count are enforced',async()=>{
  const p=await project(),raw=JSON.parse(await (await exportArchive(p)).text());raw.project.videos[0].data='QUJDRA==';await assert.rejects(importArchive(JSON.stringify(raw)),/hash/);
  await assert.rejects(checkVideo(new Blob(['not MP4'],{type:'video/mp4'})));
  for(const extra of [{duration:0},{duration:31},{width:0},{width:3841},{duration:NaN}])assert.throws(()=>validateProject({...p,videos:[{...p.videos[0],...extra}]}));
  assert.throws(()=>validateProject({...p,videos:Array(4).fill(p.videos[0])}));
  assert.throws(()=>validateProject({...p,photos:[p.videos[0]]}));
  const disguised=await makeAsset(new Blob(['<svg/>'],{type:'video/mp4'}),'fake.mp4',{width:1,height:1,duration:1});await assert.rejects(verifyAssets({...p,videos:[disguised]}));
});
test('v2 cannot silently discard a v3 clip',async()=>{const raw=JSON.parse(await (await exportArchive(await project())).text());raw.version=2;await assert.rejects(importArchive(JSON.stringify(raw)),/videoformat/);});
test('recording reuses video-only stream and waits for final dataavailable before resolving',async()=>{
  const source=stream(),states=[],r=new VideoRecorder({Recorder:FakeRecorder,onState:s=>states.push(s)}),promise=r.start(source);
  assert.equal(FakeRecorder.last.stream,source);assert.equal(FakeRecorder.last.options.mimeType,'video/mp4');assert.equal(FakeRecorder.last.interval,250);
  assert.throws(()=>r.start(source),/allerede/);r.stop();r.stop();const result=await promise;
  assert.equal(result.blob.size,mp4.length);assert.ok(result.duration>=0);assert.deepEqual(states,['recording','stopping','idle']);
  const next=r.start(source);r.stop();await next;
});
test('duration timeout and track-ended both finalize without stopping the camera themselves',async()=>{
  for(const end of ['timeout','track']){const source=stream(),r=new VideoRecorder({Recorder:FakeRecorder,seconds:0.03}),pending=r.start(source);if(end==='track')source.track.dispatchEvent(new Event('ended'));await pending;assert.equal(r.state,'idle');assert.equal(source.track.readyState,'live');}
});
test('explicit H264 is preferred over an ambiguous MP4 container when supported',async()=>{
  class H264 extends FakeRecorder {static isTypeSupported=type=>type.startsWith('video/mp4');}
  const r=new VideoRecorder({Recorder:H264}),pending=r.start(stream());assert.equal(FakeRecorder.last.options.mimeType,'video/mp4;codecs=avc1.42E01E');r.stop();await pending;
});
test('over-budget data, recorder failure and empty recordings reject without a successful asset',async()=>{
  const r=new VideoRecorder({Recorder:FakeRecorder,maxBytes:1}),result=r.start(stream());FakeRecorder.last.ondataavailable({data:clip()});await assert.rejects(result,/8 MiB/);assert.equal(r.state,'idle');
  const q=new VideoRecorder({Recorder:FakeRecorder}),failure=q.start(stream());FakeRecorder.last.onerror();await assert.rejects(failure,/afbrudt/);
  class Empty extends FakeRecorder {stop(){this.state='inactive';queueMicrotask(()=>this.onstop());}}
  const e=new VideoRecorder({Recorder:Empty}),empty=e.start(stream());e.stop();await assert.rejects(empty,/ingen video/);
});
test('unsupported, denied audio and failed start leave the recorder usable',async()=>{
  assert.throws(()=>new VideoRecorder({Recorder:null}).start(stream()),/understøttes/);
  assert.throws(()=>new VideoRecorder({Recorder:FakeRecorder}).start(stream(true)),/uden lyd/);
  class Broken extends FakeRecorder {start(){throw new Error('encoder failed');}}
  const r=new VideoRecorder({Recorder:Broken});await assert.rejects(r.start(stream()),/encoder failed/);assert.equal(r.state,'idle');
});
