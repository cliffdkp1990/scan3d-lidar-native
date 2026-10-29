#!/usr/bin/env node
// Scan3D Studio: read-only recovery of PUBLIC static resources from the exact
// production origin. No credentials, Vercel changes, browsing history, IndexedDB,
// scanned projects, private captures or Apple information are ever accessed.
import {createHash} from 'node:crypto';
import {mkdir,writeFile} from 'node:fs/promises';
import {join,dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

export const ORIGIN='https://scan3d-studio-cliff.vercel.app';
export const AUDITED_SW_SHA='1e67705b53780b6dae90e14615fc0d76259f34f15fcdc5b31dc21678270d0278';
export function digest(bytes){return createHash('sha256').update(bytes).digest('hex');}
export function safeAssetPath(raw){
  if(typeof raw!=='string'||!/^\.\//.test(raw)||raw.includes('\\')||raw.includes('%')||
    raw.includes('?')||raw.includes('#')||raw.includes('//')||
    /(^|\/)\.\.?(\/|$)/.test(raw.slice(2)))throw new Error('Unsafe static asset path');
  const relative=raw.slice(2);
  if(relative && (!/^[a-zA-Z0-9._/-]+$/.test(relative) ||
                  relative.split('/').some(p=>p==='.'||p==='..'||!p)))
    throw new Error('Invalid static asset path');
  return relative||'index.html';
}
export function staticAssets(source) {
  const match=source.match(/\bconst ASSETS\s*=\s*(\[[\s\S]*?\]);/);
  if(!match)throw new Error('Expected static resource allowlist missing');
  const inner=match[1].slice(1,-1);
  const entries=[...inner.matchAll(/'(\.\/[a-zA-Z0-9._/-]*)'/g)].map(m=>m[1]);
  const residue=inner.replace(/'(\.\/[a-zA-Z0-9._/-]*)'/g,'').replace(/[\s,]/g,'');
  if(residue||entries.length<6||entries.length>150)throw new Error('Unexpected ASSETS expression');
  const names=entries.map(safeAssetPath);
  if(new Set(names).size!==names.length) {
    // './' and './index.html' are aliases, not duplicate bytes.
    const onlyIndex=names.filter(n=>n==='index.html');
    if(onlyIndex.length!==2||new Set(names).size!==names.length-1)
      throw new Error('Duplicate static paths');
  }
  if(!names.includes('studio.html')||!names.includes('sw.js') && !source.includes("self.addEventListener"))
    throw new Error('Not the expected Studio service worker');
  return [...new Set([...names,'sw.js','manifest.webmanifest','studio.html'])].sort();
}
const EXTENSION_BUDGET={
  '.js':1_000_000,'.css':750_000,'.html':1_000_000,
  '.webmanifest':64_000,'.svg':300_000,'.png':4_000_000,
  '.jpg':15_000_000,'.jpeg':15_000_000,
  '.glb':20_000_000,'.stl':20_000_000
};
export function fileBudget(name) {
  const m=name.match(/(\.[a-z]+)$/);
  const max=m&&EXTENSION_BUDGET[m[1]];
  if(!max)throw new Error('Unapproved asset extension '+name);
  return max;
}
export async function publicRead(filename,fetcher=fetch) {
  const url=new URL('/'+filename,ORIGIN);
  if(url.origin!==ORIGIN||url.username||url.password)throw new Error('Origin mismatch');
  const response=await fetcher(url,{redirect:'manual',cache:'no-store',
    credentials:'omit',headers:{accept:'*/*'},
    signal:AbortSignal.timeout(15000)});
  if(response.status!==200 || !response.body)
    throw new Error('Public asset unavailable: '+filename+' HTTP '+response.status);
  const limit=fileBudget(filename);
  const declared=Number(response.headers.get('content-length'));
  if(declared>limit)throw new Error('Oversized static resource '+filename);
  const chunks=[];let total=0;
  for await(const chunk of response.body) {
    total+=chunk.byteLength;
    if(total>limit)throw new Error('Oversized streamed static resource '+filename);
    chunks.push(Buffer.from(chunk));
  }
  if(!total)throw new Error('Empty static file '+filename);
  return Buffer.concat(chunks);
}
export async function recover({root,fetcher=fetch,expected=AUDITED_SW_SHA}) {
  if(!/^[a-f0-9]{64}$/.test(expected))throw new Error('Expected SHA-256 required');
  const worker=await publicRead('sw.js',fetcher);
  if(digest(worker)!==expected)
    throw new Error('Production service worker changed since audited SHA: re-audit before recovery');
  const names=staticAssets(worker.toString('utf8'));
  const maxTotal=65_000_000;let total=0;
  // Read everything before writing so a failed snapshot cannot masquerade
  // as a complete and verified source tree.
  const files=[];
  for(const name of names) {
    const contents=name==='sw.js'?worker:await publicRead(name,fetcher);
    total+=contents.byteLength;
    if(total>maxTotal)throw new Error('Static resource total exceeds budget');
    files.push({name,contents,sha256:digest(contents),size:contents.byteLength});
  }
  const check=await publicRead('sw.js',fetcher);
  if(digest(check)!==expected)throw new Error('Production changed during read');
  const manifestFile=files.find(f=>f.name==='manifest.webmanifest');
  const manifest=JSON.parse(manifestFile.contents.toString('utf8'));
  if(manifest.id!=='./'||manifest.scope!=='./'||manifest.display!=='standalone')
    throw new Error('Production app identity/scope not the audited PWA');
  const receipt={schemaVersion:1,origin:ORIGIN,checkedAt:new Date().toISOString(),
    workerSHA256:expected,publicStaticAssetsOnly:true,
    indexedDBAccessed:false,appleCredentialsAccessed:false,
    installedOnPhone:false,deployed:false,completeServerSource:false,
    totalBytes:total,files:files.map(({name,sha256,size})=>({name,sha256,size}))};
  for(const file of files){
    const path=join(root,'src',file.name);
    await mkdir(dirname(path),{recursive:true});
    await writeFile(path,file.contents,{flag:'wx'});
  }
  await writeFile(join(root,'PUBLIC_ASSET_RECEIPT.json'),
    JSON.stringify(receipt,null,2)+'\n',{flag:'wx'});
  return receipt;
}
if(process.argv[1] && fileURLToPath(import.meta.url)===resolve(process.argv[1])) {
  try{
    const out=process.argv[2];
    if(!out)throw new Error('Output directory required');
    const receipt=await recover({root:out});
    console.log(JSON.stringify({origin:receipt.origin,files:receipt.files.length,
      bytes:receipt.totalBytes,sha256:receipt.workerSHA256,
      note:'Public static snapshot only, not complete original developer source. No deployment.'},null,2));
  }catch(e){console.error('UNVERIFIED: '+e.message);process.exitCode=1;}
}
