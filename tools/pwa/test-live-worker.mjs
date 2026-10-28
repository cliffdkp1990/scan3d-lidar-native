#!/usr/bin/env node
// Read-only acceptance tests against the exact public Studio worker fetched by CI.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
import {buildPatchedWorker,sha256,EXPECTED_SOURCE_SHA256,NEXT_CACHE} from './patch-live-studio.mjs';

const [originalFile,candidateFile]=process.argv.slice(2);
if(!originalFile||!candidateFile)throw new Error('Need original and candidate source files');
const original=await readFile(originalFile,'utf8');
const candidate=await readFile(candidateFile,'utf8');
const expected=buildPatchedWorker(original);
assert.equal(sha256(original),EXPECTED_SOURCE_SHA256);
assert.equal(candidate,expected);
assert(candidate.includes(NEXT_CACHE));
assert(!candidate.includes('skipWaiting('));
assert(!candidate.includes('caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith("scan3d-")'));
assert(!candidate.includes('localStorage'));
assert(!candidate.includes('indexedDB'));
let rejects=0;
for(const altered of [original+' ',original.replace('c.addAll','c.any'),'',candidate]){
  try{buildPatchedWorker(altered);}catch{rejects++;}
}
assert.equal(rejects,4,'Unknown or changed source must refuse patch');
const listeners=new Map(),updated=[],removed=[],stored=new Map(),network=[];
let online=true;
const cache={
  addAll:async assets=>{assert(assets.includes('./studio.html'));assert(assets.includes('./index.html'));},
  put:async(req,response)=>{stored.set(req.url,response)},
  match:async(req)=>stored.get(req?.url||(typeof req==='string'?req:req.toString()))
};
const self={
  registration:{scope:'https://scan3d-studio-cliff.vercel.app/'},
  location:{origin:'https://scan3d-studio-cliff.vercel.app'},
  addEventListener:(k,v)=>listeners.set(k,v),
  clients:{claim:async()=>{}}
};
const caches={
  open:async()=>cache,
  keys:async()=>['scan3d-atelier-v16',NEXT_CACHE,'scan3d-safari-other-data','unrelated-cache'],
  delete:async name=>{removed.push(name);return true}
};
const fetch=async req=>{
  network.push(req.url);
  if(!online)throw new Error('offline');
  return {ok:true,type:'basic',label:'fresh',clone(){return this}};
};
vm.runInNewContext(candidate,{self,caches,fetch,URL,console});
function dispatch(url,method='GET',mode='same-origin') {
  let answer=null;
  listeners.get('fetch')({request:{url,method,mode},respondWith(value){answer=value;}});
  return answer;
}
const base='https://scan3d-studio-cliff.vercel.app/';
for(const filename of ['atelier.js','atelier.css','studio.html']){
  const reply=dispatch(base+filename);
  assert(reply,'Known static asset must be intercepted');
  assert.equal((await reply).label,'fresh');
}
const first=network.length;
const again=dispatch(base+'atelier.js');
assert.equal((await again).label,'fresh');
assert.equal(network.length,first+1,'Network must be checked before cached JavaScript');
online=false;
assert.equal((await dispatch(base+'atelier.js')).label,'fresh','Offline cache must still load');
for(const path of ['scan3d-data/secret.json','private-video.mp4','api/projects','unsupported.js']){
  assert.equal(dispatch(base+path),null,'Never intercept user projects/exports: '+path);
}
assert.equal(dispatch('https://example.org/studio.html'),null);
assert.equal(dispatch(base+'atelier.css','POST'),null);
let install=null;listeners.get('install')({waitUntil(x){install=x}});
await install;
let active=null;listeners.get('activate')({waitUntil(x){active=x}});
await active;
assert.deepEqual(removed,['scan3d-atelier-v16']);
assert(!listeners.has('message'),'Worker must not force update from a message');
assert.equal(typeof self.skipWaiting,'undefined','Worker must not force active capture interruption');
console.log('Studio verified production SHA, unchanged asset list, network-first JS, offline fallback, no user file interception, no auto-reload and narrow cache cleanup: PASS');
