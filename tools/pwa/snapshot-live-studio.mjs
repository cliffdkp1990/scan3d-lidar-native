#!/usr/bin/env node
/**
 * Read-only and strictly bounded backup of the PUBLIC, EXACT Scan3D Studio
 * production assets for source recovery and review. NOT a release.
 * Never fetch cookies, project files, APIs, logins, private URLs or iPhone data.
 */
import {createHash} from 'node:crypto';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve,dirname,join} from 'node:path';
import {pathToFileURL} from 'node:url';

export const ORIGIN='https://scan3d-studio-cliff.vercel.app';
export const SOURCE_SHA='1e67705b53780b6dae90e14615fc0d76259f34f15fcdc5b31dc21678270d0278';
const MAX_FILE=12*1024*1024;
const MAX_TOTAL=40*1024*1024;
const MAX_FILES=60;
const extensions=new Set(['.html','.js','.css','.webmanifest','.jpg','.jpeg','.png','.svg','.glb','.stl']);
const digest=data=>createHash('sha256').update(data).digest('hex');

export function parseStaticAssets(worker) {
  if(digest(Buffer.from(worker,'utf8'))!==SOURCE_SHA)
    throw new Error('Live worker differs from previously audited source SHA; no source backup');
  const match=worker.match(/const ASSETS=(\[[\s\S]*?\]);\r?\nself\.addEventListener\('install'/);
  if(!match)throw new Error('No audited static asset list');
  let paths;
  try { paths=JSON.parse(match[1].replace(/'/g,'"')); }
  catch { throw new Error('Unexpected asset list format: refuse to execute downloaded JavaScript'); }
  if(!Array.isArray(paths)||paths.length<8||paths.length>MAX_FILES||
      !paths.every(x=>typeof x==='string'))throw new Error('Unexpected asset list size');
  const result=new Map();
  for(const name of paths) {
    if(name==='./')continue; // ./ and ./index.html both serve one root document
    const parts=name.split('/');
    if(parts[0]!=='.'||parts.length<2||parts.slice(1).some(x=>!x||x==='.'||x==='..'))
      throw new Error('Unsafe or nonrelative public asset path');
    if(!/^[a-zA-Z0-9_./-]+$/.test(name)||/[?#\\]/.test(name))
      throw new Error('Queries, escapes or external URLs are never accepted');
    const file=parts.slice(1).join('/');
    const ext='.'+(file.split('.').at(-1)||'').toLowerCase();
    if(!extensions.has(ext))throw new Error('Non-static file in public cache manifest');
    const url=new URL(name,ORIGIN+'/');
    if(url.origin!==ORIGIN||url.username||url.password||
       url.pathname!=='/'+file)throw new Error('Asset URL is not an exact public origin path');
    if(result.has(file))throw new Error('Duplicate public file');
    result.set(file,url.toString());
  }
  if(!result.has('index.html')||!result.has('studio.html')||
     !result.has('atelier.js')||!result.has('manifest.webmanifest'))
    throw new Error('Important original Studio source files are absent');
  result.set('sw.js',ORIGIN+'/sw.js');
  return result;
}

export async function retrieve(url,limit=MAX_FILE) {
  if(!(url.startsWith(ORIGIN+'/'))||new URL(url).origin!==ORIGIN)
    throw new Error('Blocked non-Scan3D URL');
  const response=await fetch(url,{
    method:'GET',redirect:'manual',cache:'no-store',
    headers:{Accept:'*/*'},
    signal:AbortSignal.timeout(16000)
  });
  if(response.status!==200)throw new Error('Non-public, redirected or unavailable static asset: HTTP '+response.status);
  const len=Number(response.headers.get('content-length'));
  if(Number.isFinite(len)&&len>limit)throw new Error('File exceeds strict maximum size');
  const output=[];
  let total=0;
  for await(const chunk of response.body){
    total+=chunk.length;
    if(total>limit)throw new Error('Downloaded file exceeds limit');
    output.push(chunk);
  }
  return {bytes:Buffer.concat(output),contentType:response.headers.get('content-type')||''};
}

export async function backup(sourceDir,outputDir,{retrieveFile=retrieve}={}) {
  const original=await readFile(join(sourceDir,'sw.js'),'utf8');
  const names=parseStaticAssets(original);
  const evidence=JSON.parse(await readFile(join(sourceDir,'LIVE_PRODUCTION_AUDIT.json'),'utf8'));
  if(evidence.origin!==ORIGIN||evidence.accessible!==true||
     evidence.files?.find(x=>x.file==='sw.js')?.sha256!==SOURCE_SHA||
     evidence.files?.find(x=>x.file==='manifest.webmanifest')?.status!=='HTTP 200')
    throw new Error('Untrusted or changed original public audit receipt');
  // Original Vercel deployment file, fetched through the owner's Vercel
  // connection and committed as a non-secret, versioned reference, not guessed.
  const config=await readFile(new URL('./studio-vercel-original.json',import.meta.url));
  const rules=JSON.parse(config.toString('utf8'));
  const header=(source,key)=>rules.headers?.find(r=>r.source===source)?.headers
    ?.find(h=>h.key===key)?.value;
  if(rules.cleanUrls!==false||
     header('/sw.js','Cache-Control')!=='no-cache'||
     header('/index.html','Cache-Control')!=='no-cache'||
     header('/(.*)','X-Content-Type-Options')!=='nosniff'||
     header('/(.*)','Referrer-Policy')!=='no-referrer'||
     header('/(.*)','X-Frame-Options')!=='DENY')
    throw new Error('Original Vercel security/cache headers changed');
  const destination=resolve(outputDir);
  const src=join(destination,'original-public-source');
  const data=[];let total=0;
  for(const [name,url] of [...names].sort(([a],[b])=>a.localeCompare(b))){
    const result=name==='sw.js'
      ? {bytes:Buffer.from(original,'utf8'),contentType:'application/javascript'}
      : await retrieveFile(url,MAX_FILE);
    total+=result.bytes.length;
    if(total>MAX_TOTAL)throw new Error('Aggregate source copy exceeds limit');
    if(result.bytes.length===0)throw new Error('Empty public source asset: '+name);
    const filename=join(src,name);
    if(!filename.startsWith(src+'/'))throw new Error('Unsafe target');
    await mkdir(dirname(filename),{recursive:true});
    await writeFile(filename,result.bytes,{flag:'wx'});
    data.push({file:name,bytes:result.bytes.length,sha256:digest(result.bytes),
      contentType:result.contentType});
  }
  // The config was read from the authenticated project's actual deployed
  // source tree; do not try to fetch it from a public HTTP URL.
  await writeFile(join(src,'vercel.json'),config,{flag:'wx'});
  total+=config.length;
  data.push({file:'vercel.json',bytes:config.length,sha256:digest(config),
    contentType:'application/json',provenance:'Vercel deployment source connector'});
  const manifest=JSON.parse(await readFile(join(src,'manifest.webmanifest'),'utf8'));
  if(manifest.display!=='standalone'||manifest.id!=='./'||manifest.start_url!=='./index.html'||
     manifest.scope!=='./')throw new Error('Original PWA app identity changed');
  // Recheck this exact public source. If Vercel changed mid-run, do NOT
  // claim a consistent historical snapshot, even when all paths existed.
  const current=await retrieveFile(ORIGIN+'/sw.js',MAX_FILE);
  if(digest(current.bytes)!==SOURCE_SHA)throw new Error('Production worker changed during backup');
  const receipt={
    source:'public HTTPS files only, as listed in audited production worker',
    origin:ORIGIN,createdAt:new Date().toISOString(),
    referenceWorkerSHA256:SOURCE_SHA,actualWorkerSHA256:digest(Buffer.from(original,'utf8')),
    originalAppIdentity:{id:manifest.id,start_url:manifest.start_url,scope:manifest.scope},
    files:data,filesVerified:data.length,bytesVerified:total,
    containsUserScans:false,containsPrivateFiles:false,
    containsVercelBuildConfig:true,isCompleteDeploymentSource:false,
    writeToProduction:false,readyForDeployment:false,
    nativeLiDAR:false,physicalIPhoneTested:false
  };
  await mkdir(destination,{recursive:true});
  await writeFile(join(destination,'PUBLIC_SOURCE_RECEIPT.json'),JSON.stringify(receipt,null,2)+'\n',{flag:'wx'});
  return receipt;
}

if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href) {
  if(process.argv.length!==4)throw new Error('Usage: node snapshot-live-studio.mjs <public-audit-dir> <backup-folder>');
  const result=await backup(process.argv[2],process.argv[3]);
  console.log(JSON.stringify({
    verifiedAssets:result.filesVerified,bytes:result.bytesVerified,
    worker:result.referenceWorkerSHA256,
    originalAppIdentity:result.originalAppIdentity,
    noLogin:true,noProductionWrite:true,deployable:false
  },null,2));
}
