#!/usr/bin/env node
// Offline proposal only. Takes a hash-verifiable copy of the deployed public
// Studio assets; never makes changes to Vercel, iPhone or user project data.
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {join,dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {AUDITED_SW_SHA,digest,staticAssets} from './recover-public-atelier.mjs';

export function replacementWorker(original) {
  const match=original.match(/\bconst ASSETS\s*=\s*(\[[\s\S]*?\]);/);
  if(!match||!original.includes("const CACHE='scan3d-atelier-v16';"))
    throw new Error('Not the audited Atelier v16 service worker');
  const assets=staticAssets(original);
  if(assets.includes('studio-safe-updates.js'))
    throw new Error('Update module already present');
  const allowlist="const ASSETS="+match[1].replace(/\];$/,",'./studio-safe-updates.js'];");
  return [
    '/* Scan3D Atelier v17: network-first source code; no user data writes. */',
    "const CACHE='scan3d-atelier-v17-safe-reopen';",
    "const PREFIX='scan3d-atelier-';",
    allowlist,
    "const ALLOWED=new Set(ASSETS.map(path=>new URL(path,self.registration.scope).pathname));",
    "const NETWORK_FIRST=/\\.(?:js|css|html|webmanifest)$/i;",
    "function allowed(request) {",
    " const url=new URL(request.url);",
    " return request.method==='GET'&&url.origin===self.location.origin&&ALLOWED.has(url.pathname);",
    "}",
    "function cacheable(response) {return response&&response.ok&&response.type==='basic';}",
    "async function networkFirst(request) {",
    " const cache=await caches.open(CACHE);",
    " try {",
    "  const response=await fetch(request);",
    "  if(!cacheable(response))throw new Error('Non-cacheable static response');",
    "  await cache.put(request,response.clone()).catch(()=>{});",
    "  return response;",
    " }catch(error) {",
    "  const cached=await cache.match(request,{ignoreSearch:true});",
    "  if(cached)return cached;",
    "  if(request.mode==='navigate'){",
    "   const fallback=await cache.match(new URL('./index.html',self.registration.scope));",
    "   if(fallback)return fallback;",
    "  }",
    "  throw error;",
    " }",
    "}",
    "async function cacheThenNetwork(request) {",
    " const cache=await caches.open(CACHE);",
    " const cached=await cache.match(request,{ignoreSearch:true});",
    " if(cached)return cached;",
    " const response=await fetch(request);",
    " if(cacheable(response))await cache.put(request,response.clone()).catch(()=>{});",
    " return response;",
    "}",
    "self.addEventListener('install',event=>{",
    " // Do not skipWaiting: the old scanner keeps running until every app window is closed.",
    " event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(ASSETS)));",
    "});",
    "self.addEventListener('activate',event=>{",
    " event.waitUntil((async()=>{",
    "  const names=await caches.keys();",
    "  await Promise.all(names.filter(name=>name.startsWith(PREFIX)&&name!==CACHE).map(name=>caches.delete(name)));",
    "  await self.clients.claim();",
    " })());",
    "});",
    "self.addEventListener('fetch',event=>{",
    " if(!allowed(event.request))return; // never intercept project/export endpoints",
    " const url=new URL(event.request.url);",
    " if(event.request.mode==='navigate'||NETWORK_FIRST.test(url.pathname))",
    "  event.respondWith(networkFirst(event.request));",
    " else event.respondWith(cacheThenNetwork(event.request));",
    "});",
    ""
  ].join('\n');
}
export function registrationHelper() {
  return [
    "/* Check updates when Safari foregrounds, but never reload during active capture. */",
    "(()=>{'use strict';",
    "if(!('serviceWorker' in navigator)||!isSecureContext)return;",
    "let registration=null,lastCheck=0;",
    "const check=async()=>{",
    " if(!registration||document.hidden||!navigator.onLine)return;",
    " if(Date.now()-lastCheck<60000)return;",
    " lastCheck=Date.now();",
    " try{await registration.update();}catch{/* Remain usable offline. */}",
    "};",
    "navigator.serviceWorker.register('./sw.js',{scope:'./',updateViaCache:'none'})",
    " .then(reg=>{registration=reg;void check();}).catch(()=>{});",
    "document.addEventListener('visibilitychange',()=>{if(!document.hidden)void check();});",
    "window.addEventListener('pageshow',()=>void check());",
    "window.addEventListener('focus',()=>void check());",
    "})();",
    ""
  ].join('\n');
}
export function injectHelper(html) {
  if(!/<\/body>/i.test(html)||html.includes('studio-safe-updates.js'))
    throw new Error('Unexpected or already modified Studio HTML');
  return html.replace(/<\/body>/i,'<script defer src="./studio-safe-updates.js"></script></body>');
}
export async function prepare(snapshot,output) {
  const receipt=JSON.parse(await readFile(join(snapshot,'PUBLIC_ASSET_RECEIPT.json'),'utf8'));
  if(receipt.schemaVersion!==1||receipt.workerSHA256!==AUDITED_SW_SHA||
     receipt.publicStaticAssetsOnly!==true||
     receipt.origin!=='https://scan3d-studio-cliff.vercel.app')
    throw new Error('Snapshot provenance does not match audited production');
  const files=new Map();
  for(const f of receipt.files){
    if(!f.name||files.has(f.name))throw new Error('Duplicate snapshot file');
    const bytes=await readFile(join(snapshot,'src',f.name));
    if(bytes.length!==f.size||digest(bytes)!==f.sha256)
      throw new Error('Snapshot file modified: '+f.name);
    files.set(f.name,bytes);
  }
  const original=files.get('sw.js');
  if(!original||digest(original)!==AUDITED_SW_SHA)
    throw new Error('Production worker hash mismatch');
  const patched=replacementWorker(original.toString('utf8'));
  for(const name of ['index.html','studio.html']){
    if(!files.has(name))throw new Error('Missing original Studio HTML '+name);
    files.set(name,Buffer.from(injectHelper(files.get(name).toString('utf8'))));
  }
  files.set('sw.js',Buffer.from(patched));
  files.set('studio-safe-updates.js',Buffer.from(registrationHelper()));
  for(const [name,bytes] of files) {
    const path=join(output,'src',name);
    await mkdir(dirname(path),{recursive:true});
    await writeFile(path,bytes,{flag:'wx'});
  }
  const originalManifest=receipt.files.find(x=>x.name==='manifest.webmanifest')?.sha256;
  const patchedManifest=digest(files.get('manifest.webmanifest'));
  if(!originalManifest||originalManifest!==patchedManifest)
    throw new Error('PWA manifest identity/scope may have changed');
  const proof={schemaVersion:1,origin:receipt.origin,
    originalWorkerSHA256:AUDITED_SW_SHA,proposedWorkerSHA256:digest(files.get('sw.js')),
    originalManifestSHA256:originalManifest,proposedManifestSHA256:patchedManifest,
    publicAssetsOnly:true,deployed:false,installedOnPhone:false,
    changedNames:['sw.js','index.html','studio.html','studio-safe-updates.js'],
    files:[...files].map(([name,bytes])=>({name,bytes:bytes.length,sha256:digest(bytes)}))};
  await writeFile(join(output,'SAFE_UPDATE_RECEIPT.json'),JSON.stringify(proof,null,2)+'\n',{flag:'wx'});
  return proof;
}
if(process.argv[1] && fileURLToPath(import.meta.url)===resolve(process.argv[1])) {
  try{
    const [snapshot,output]=process.argv.slice(2);
    if(!snapshot||!output)throw new Error('Snapshot and separate preview directory required');
    const proof=await prepare(snapshot,output);
    console.log(JSON.stringify({patched:proof.changedNames,
      identityUnchanged:proof.originalManifestSHA256===proof.proposedManifestSHA256,
      productionModified:false},null,2));
  }catch(e){console.error('UNVERIFIED: '+e.message);process.exitCode=1;}
}
