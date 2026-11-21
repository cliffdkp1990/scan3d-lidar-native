import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {mkdtemp,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {digest,staticAssets,safeAssetPath,recover} from './recover-public-atelier.mjs';
import {replacementWorker,registrationHelper,injectHelper,prepare} from './prepare-studio-update.mjs';

const ORIGINAL="/* Test-only synthetic page, not a real Vercel copy. */\n"+
 "const CACHE='scan3d-atelier-v16';\n"+
 "const ASSETS=['./','./index.html','./studio.html','./app.js','./studio.js','./atelier.css',"+
 "'./manifest.webmanifest','./assets/icon-192.png'];\n"+
 "self.addEventListener('install',()=>{});\n";
function syntheticFetcher(worker=ORIGINAL){
  const manifest=JSON.stringify({id:'./',scope:'./',display:'standalone'});
  const values=new Map([
    ['sw.js',worker],['index.html','<!doctype html><html><body>Hi</body></html>'],
    ['studio.html','<!doctype html><html><body>Studio</body></html>'],
    ['app.js','console.log(1)'],['studio.js','console.log(2)'],
    ['atelier.css','body{color:black}'],['manifest.webmanifest',manifest],
    ['assets/icon-192.png','png-test-fixture']]);
  return async url=>{
    const key=url.pathname.slice(1);
    return new Response(values.get(key)||'',{status:values.has(key)?200:404});
  };
}
function runtime(worker){
  const listeners=new Map(),memory=new Map(),removed=[],network=[];
  const cache={
    addAll:async assets=>{memory.set('precached',assets);},
    put:async(req,res)=>{memory.set(typeof req==='string'?req:req.url,res);},
    match:async(req)=>memory.get(typeof req==='string'?req:req.href||req.url)
  };
  const caches={
    open:async()=>cache,
    keys:async()=>['scan3d-atelier-v16','scan3d-atelier-v17-safe-reopen',
                   'scan3d-other-app-cache','precious-user-data'],
    delete:async name=>{removed.push(name);return true;}
  };
  const self={location:{origin:'https://scan3d-studio-cliff.vercel.app'},
    registration:{scope:'https://scan3d-studio-cliff.vercel.app/'},
    addEventListener:(name,callback)=>listeners.set(name,callback),
    clients:{claim:async()=>{}}
  };
  const fetch=async req=>{
    network.push(req.url);
    return {ok:true,type:'basic',clone(){return this;},label:'network'};
  };
  vm.runInNewContext(worker,{URL,caches,self,fetch,console});
  const request=(url,method='GET',mode='same-origin')=>({url,method,mode});
  async function event(name,obj={}){
    let pending=null,response=null;
    listeners.get(name)?.({...obj,waitUntil:p=>{pending=p;},
      respondWith:p=>{response=p;}});
    if(pending)await pending;
    return response;
  }
  return{event,request,memory,removed,network};
}
test('accept only predetermined public same-origin static paths',()=>{
  const names=staticAssets(ORIGINAL);
  assert(names.includes('studio.html'));
  assert(names.includes('manifest.webmanifest'));
  assert(names.includes('sw.js'));
  assert.equal(names.filter(x=>x==='index.html').length,1);
  for(const value of ['../../private.txt','https://external.example','./../secrets',
                      './api/token','./..','./file?secret=1','./bad%2Fname'])
    assert.throws(()=>safeAssetPath(value));
  assert.throws(()=>staticAssets("const ASSETS=['./','./studio.html',process.env.TOKEN];"));
});
test('read-only recovery produces provenance and never changes any source file',async()=>{
  const temp=await mkdtemp(join(tmpdir(),'atelier-audit-'));
  try{
    const receipt=await recover({root:temp,fetcher:syntheticFetcher(),expected:digest(Buffer.from(ORIGINAL))});
    assert.equal(receipt.files.some(f=>f.name==='studio.html'),true);
    assert.equal(receipt.indexedDBAccessed,false);
    assert.equal(receipt.deployed,false);
    const bytes=await readFile(join(temp,'src','sw.js'));
    assert.equal(bytes.toString(),ORIGINAL);
    await assert.rejects(()=>prepare(temp,join(temp,'preview')),/provenance/);
  }finally{await rm(temp,{recursive:true,force:true});}
});
test('preview worker is syntactically valid and never auto-takes over active scanning',async()=>{
  const worker=replacementWorker(ORIGINAL);
  new vm.Script(worker);
  assert(worker.includes('studio-safe-updates.js'));
  assert(!/\.skipWaiting\s*\(/.test(worker), 'Updated worker must not call skipWaiting');
  assert(!worker.includes('location.reload'));
  const runtimeWorker=runtime(worker);
  await runtimeWorker.event('install');
  assert(runtimeWorker.memory.get('precached').includes('./studio-safe-updates.js'));
  await runtimeWorker.event('activate');
  assert.deepEqual(runtimeWorker.removed,['scan3d-atelier-v16']);
  assert(!runtimeWorker.removed.includes('precious-user-data'));
});
test('new JS is fetched online; private projects and video never intercepted',async()=>{
  const sw=runtime(replacementWorker(ORIGINAL));
  const base='https://scan3d-studio-cliff.vercel.app/';
  for(let i=0;i<2;i++){
    const response=await sw.event('fetch',{request:sw.request(base+'app.js')});
    assert.equal((await response).label,'network');
  }
  assert.equal(sw.network.length,2);
  for(const url of ['api/projects','user-video.mp4','private-photos.json']){
    assert.equal(await sw.event('fetch',{request:sw.request(base+url)}),null);
  }
  assert.equal(await sw.event('fetch',{request:sw.request(base+'app.js','POST')}),null);
  assert.equal(await sw.event('fetch',{request:sw.request('https://evil.example/app.js')}),null);
});
test('preview helper does not reload, sign in, send scans or overwrite browser projects',()=>{
  const helper=registrationHelper();
  new vm.Script(helper);
  assert(helper.includes('registration.update()'));
  for(const forbidden of ['location.reload','skipWaiting','indexedDB.deleteDatabase',
      'localStorage.clear','fetch('])
    assert(!helper.includes(forbidden),forbidden);
  const html=injectHelper('<!doctype html><body>Studio</body></html>');
  assert(html.includes('studio-safe-updates.js'));
  assert.throws(()=>injectHelper(html),/already modified/);
});
