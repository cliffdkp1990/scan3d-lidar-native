import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import {canSwitchPWA} from '../pwa-updates.mjs';

const swUrl=new URL('../sw.js',import.meta.url);
const ORIGIN='https://scan3d.example';
const SCOPE=ORIGIN+'/';
const body=()=>readFile(swUrl,'utf8');
function mockWorker(code,withNetwork=true){
  const listeners=new Map();
  const saved=new Map();
  const deleted=[];
  const network=[];
  const worker={
    registration:{scope:SCOPE},
    location:{origin:ORIGIN},
    addEventListener(type,callback){listeners.set(type,callback);},
    skipWaiting(){return Promise.resolve('activated');},
    clients:{claim(){return Promise.resolve();}}
  };
  const cache={
    addAll:async assets=>{saved.set('precached',assets);},
    match:async req=>saved.get(typeof req==='string'?req:req.url),
    put:async(req,response)=>{saved.set(typeof req==='string'?req:req.url,response);}
  };
  const caches={
    open:async()=>cache,
    keys:async()=>['other-project-keep','scan3d-safari-shell-old','scan3d-safari-shell-20261028-1'],
    delete:async name=>{deleted.push(name);return true}
  };
  const fetch=async req=>{
    network.push(req.url);
    if(!withNetwork)throw new Error('offline');
    return {ok:true,type:'basic',clone(){return this;},label:'online'};
  };
  vm.runInNewContext(code,{self:worker,URL,caches,fetch,console});
  return {listeners,saved,deleted,network};
}
async function dispatchFetch(mock,request) {
  let response=null;
  mock.listeners.get('fetch')({
    request,
    respondWith(value){response=value;}
  });
  return response;
}
test('PWA updates cannot interrupt drafts, recordings, cameras, recovery or RGBD',()=>{
  assert.equal(canSwitchPWA(),true);
  for (const change of [
    {busy:true},{dirty:true},{recording:true},{recovery:true},
    {camera:'active'},{camera:'pending'},{depth:'live'},{depth:'connecting'}
  ]) assert.equal(canSwitchPWA(change),false,JSON.stringify(change));
});
test('worker JavaScript compiles and caches only fixed same-origin app shell paths',async()=>{
  const sw=mockWorker(await body());
  let install=null;
  sw.listeners.get('install')({waitUntil(value){install=value;}});
  await install;
  const paths=sw.saved.get('precached');
  assert(paths.includes('./index.html'));
  assert(paths.includes('./pwa-updates.mjs'));
  assert(paths.includes('./app.mjs'));
  assert.equal(paths.length,new Set(paths).size);
  assert(paths.every(x=>x.startsWith('./')));
  assert(!paths.some(x=>/api\/|blob:|photos|videos|localStorage|indexedDB|project-backup/i.test(x)));
});
test('online app JS refreshes on every request; exports and external media bypass worker',async()=>{
  const sw=mockWorker(await body());
  const ok={url:SCOPE+'app.mjs',method:'GET',mode:'same-origin'};
  let r=await dispatchFetch(sw,ok);
  assert(r);
  assert.equal((await r).label,'online');
  assert.equal(sw.network.length,1);
  assert.equal(sw.saved.has(ok.url),true);
  await dispatchFetch(sw,ok);assert.equal(sw.network.length,2);
  for(const request of [
    {url:SCOPE+'api/projects',method:'GET',mode:'same-origin'},
    {url:SCOPE+'my-video.mp4',method:'GET',mode:'same-origin'},
    {url:'https://other.example/app.mjs',method:'GET',mode:'same-origin'},
    {url:SCOPE+'app.mjs',method:'POST',mode:'same-origin'}
  ])assert.equal(await dispatchFetch(sw,request),null);
});
test('activation deletes only Scan3D-specific obsolete shell caches',async()=>{
  const sw=mockWorker(await body());
  let completion;
  sw.listeners.get('activate')({waitUntil(value){completion=value;}});
  await completion;
  assert.deepEqual(sw.deleted,['scan3d-safari-shell-old']);
});
test('service worker stays waiting until explicit same-origin user update request',async()=>{
  const sw=mockWorker(await body());
  let requested=false;
  sw.listeners.get('message')({data:{type:'SCAN3D_ACTIVATE_WHEN_SAFE'},
    source:{url:'https://other.example/'},waitUntil(){requested=true;}});
  assert.equal(requested,false);
  sw.listeners.get('message')({data:{type:'SCAN3D_ACTIVATE_WHEN_SAFE'},
    source:{url:SCOPE},waitUntil(){requested=true;}});
  assert.equal(requested,true);
  assert(!(/self\.skipWaiting\(\)/.test((await body()).split("self.addEventListener('install'")[1].split("self.addEventListener('message'")[0])));
});
