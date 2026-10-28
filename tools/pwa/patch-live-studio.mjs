#!/usr/bin/env node
// Review-only, exact-hash patch generator for the ACTUAL public Vercel Atelier SW.
// Writes a candidate only. NEVER deploys, signs, logs in or edits live pages.
import {createHash} from 'node:crypto';
import {readFile,writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';

export const EXPECTED_SOURCE_SHA256='1e67705b53780b6dae90e14615fc0d76259f34f15fcdc5b31dc21678270d0278';
export const NEXT_CACHE='scan3d-atelier-v17-20261028';
export function sha256(text) {
  return createHash('sha256').update(text,'utf8').digest('hex');
}
export function buildPatchedWorker(original) {
  if(typeof original!=='string'||sha256(original)!==EXPECTED_SOURCE_SHA256)
    throw new Error('Production service worker changed; refusing to patch an unknown version.');
  const parsed=original.match(/const ASSETS=(\[[\s\S]+?\]);\r?\nself\.addEventListener\('install'/);
  if(!parsed)throw new Error('Could not extract the original exact static asset list.');
  const assets=parsed[1];
  // The only generated code is a small static service worker. No app data is touched.
  const lines=[
    '/* Scan3D Atelier: audited offline shell, network-first updates, no capture interruption. */',
    "const PREFIX='scan3d-atelier-';",
    "const CACHE='"+NEXT_CACHE+"';",
    'const ASSETS='+assets+';',
    'const PATHS=new Set(ASSETS.map(path=>new URL(path,self.registration.scope).pathname));',
    'function safeAsset(request){',
    '  const url=new URL(request.url);',
    "  return request.method==='GET'&&url.origin===self.location.origin&&",
    '    !url.username&&!url.password&&PATHS.has(url.pathname);',
    '}',
    'async function networkFirst(request){',
    '  const cache=await caches.open(CACHE);',
    '  try{',
    '    const fresh=await fetch(request);',
    "    if(!fresh.ok||fresh.type!=='basic')throw new Error('Static asset unavailable');",
    '    await cache.put(request,fresh.clone()).catch(()=>{});',
    '    return fresh;',
    '  }catch(error){',
    '    const hit=await cache.match(request,{ignoreSearch:true});',
    '    if(hit)return hit;',
    "    if(request.mode==='navigate'){",
    "      const fallback=await cache.match(new URL('./index.html',self.registration.scope));",
    '      if(fallback)return fallback;',
    '    }',
    '    throw error;',
    '  }',
    '}',
    "self.addEventListener('install',event=>{",
    '  // No forced activation. New worker waits until previous app windows close.',
    '  event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(ASSETS)));',
    '});',
    "self.addEventListener('activate',event=>{",
    '  event.waitUntil((async()=>{',
    '    const keys=await caches.keys();',
    '    await Promise.all(keys.filter(key=>key.startsWith(PREFIX)&&key!==CACHE)',
    '      .map(key=>caches.delete(key)));',
    '    await self.clients.claim();',
    '  })());',
    '});',
    "self.addEventListener('fetch',event=>{",
    '  if(safeAsset(event.request))event.respondWith(networkFirst(event.request));',
    '});'
  ];
  const result=lines.join('\n')+'\n';
  if(result.includes('skipWaiting(')||result.includes('indexedDB')||
     result.includes('localStorage')||result.includes('location.reload('))
    throw new Error('Generated worker has a forbidden operation.');
  return result;
}
if(process.argv[1]&&fileURLToPath(import.meta.url)===resolve(process.argv[1])){
  if(process.argv.length!==4)throw new Error('Usage: node patch-live-studio.mjs <audited-sw.js> <candidate-sw.js>');
  const raw=await readFile(process.argv[2],'utf8');
  const next=buildPatchedWorker(raw);
  await writeFile(process.argv[3],next,{encoding:'utf8',flag:'wx'});
  console.log(JSON.stringify({sourceSHA256:sha256(raw),candidateSHA256:sha256(next),
    changedLive:false,filesWritten:1,patchOnly:true}));
}
