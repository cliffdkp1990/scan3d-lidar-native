#!/usr/bin/env node
// Synthetic WebKit iPhone-sized acceptance test of the exact verified Studio
// public snapshot. It never contacts a private user's phone or Vercel writes.
import {webkit} from '@playwright/test';
import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import {resolve,join,extname,sep} from 'node:path';
import assert from 'node:assert/strict';
const root=resolve(process.env.STUDIO_PREVIEW_SRC||'');
if(!process.env.STUDIO_PREVIEW_SRC)throw new Error('STUDIO_PREVIEW_SRC required');
const mimes={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8',
 '.css':'text/css; charset=utf-8','.webmanifest':'application/manifest+json',
 '.svg':'image/svg+xml','.png':'image/png','.jpg':'image/jpeg',
 '.stl':'model/stl','.glb':'model/gltf-binary'};
const server=createServer(async(req,res)=>{
 try{
  const raw=new URL(req.url,'http://127.0.0.1').pathname;
  const decoded=decodeURIComponent(raw);
  const path=resolve(root,'.'+(decoded==='/'?'/index.html':decoded));
  if(!path.startsWith(root+sep)){res.writeHead(404).end();return;}
  const bytes=await readFile(path);
  res.writeHead(200,{'Content-Type':mimes[extname(path)]||'application/octet-stream',
    'Content-Length':String(bytes.length),
    'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});
  res.end(bytes);
 }catch{res.writeHead(404).end('Not found');}
});
await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
const url='http://127.0.0.1:'+server.address().port+'/';
let browser,context;
try{
 browser=await webkit.launch({headless:true});
 context=await browser.newContext({viewport:{width:430,height:932},
   deviceScaleFactor:3,isMobile:true,hasTouch:true,
   serviceWorkers:'allow'});
 const page=await context.newPage();
 await page.goto(url,{waitUntil:'domcontentloaded',timeout:20000});
 await page.locator('a[href*="studio.html?mode=capture"]').first().waitFor({timeout:10000});
 const registration=await page.evaluate(async()=>{
   const ready=await navigator.serviceWorker.ready;
   return {scope:ready.scope,active:!!ready.active};
 });
 assert(registration.active,'PWA must have an active offline worker');
 const storedCaches=await page.evaluate(async()=>await window.caches.keys());
 assert(storedCaches.includes('scan3d-atelier-v17-safe-reopen'),
   'Expected safe versioned offline shell not active');
 // Never write into the real app's IndexedDB store. Synthetic isolated fixture.
 await page.evaluate(async()=>{
   localStorage.setItem('scan3d-test-only-retain','project-data-survived');
   await new Promise((resolve,reject)=>{
     const req=indexedDB.open('scan3d-pwa-ci-test-fixture',1);
     req.onupgradeneeded=()=>req.result.createObjectStore('draft');
     req.onerror=()=>reject(req.error);
     req.onsuccess=()=>{
       const db=req.result,transaction=db.transaction('draft','readwrite');
       transaction.objectStore('draft').put('kept','local-project');
       transaction.oncomplete=()=>{db.close();resolve();};
       transaction.onerror=()=>reject(transaction.error);
     };
   });
 });
 await context.setOffline(true);
 await page.reload({waitUntil:'domcontentloaded',timeout:15000});
 assert((await page.title()).includes('Scan3D'),'Offline home-screen view missing');
 await page.goto(url+'studio.html?mode=library',{waitUntil:'domcontentloaded',timeout:15000});
 const persisted=await page.evaluate(async()=>{
   const local=localStorage.getItem('scan3d-test-only-retain');
   const draft=await new Promise((resolve,reject)=>{
     const req=indexedDB.open('scan3d-pwa-ci-test-fixture');
     req.onerror=()=>reject(req.error);
     req.onsuccess=()=>{
       const db=req.result,transaction=db.transaction('draft','readonly');
       const data=transaction.objectStore('draft').get('local-project');
       data.onsuccess=()=>{db.close();resolve(data.result);};
       data.onerror=()=>reject(data.error);
     };
   });
   return {local,draft};
 });
 assert.equal(persisted.local,'project-data-survived');
 assert.equal(persisted.draft,'kept');
 console.log(JSON.stringify({source:'audited production static assets with pending safe update',
   engine:'Playwright WebKit',viewport:'430x932',home:true,studio:true,
   offline:true,indexedDBPreserved:true,localStoragePreserved:true,
   physicalIPhone:false,productionDeployed:false},null,2));
}finally{
 if(context)await context.close().catch(()=>{});
 if(browser)await browser.close().catch(()=>{});
 await new Promise(resolve=>server.close(resolve));
}
