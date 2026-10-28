#!/usr/bin/env node
// Read-only audit of the *actual* fixed Scan3D Studio production domain.
// No cookies, login, tokens, publishing, source modifications or capture data.
import {createHash} from 'node:crypto';
import {writeFile,mkdir} from 'node:fs/promises';
import {join} from 'node:path';

const BASE='https://scan3d-studio-cliff.vercel.app';
const FILES=[
  {name:'manifest.webmanifest',limit:32768,expected:'json'},
  {name:'sw.js',limit:262144,expected:'js'},
  {name:'index.html',limit:262144,expected:'html'}
];
const out=process.argv[2]||'./pwa-audit';
const report={checkedAt:new Date().toISOString(),origin:BASE,readOnly:true,
  noLoginAttempted:true,productionModified:false,files:[],issues:[]};

async function readPublic(path,maxBytes) {
  const url=new URL('/'+path,BASE);
  if(url.origin!==BASE)throw new Error('Unexpected origin');
  const response=await fetch(url,{
    method:'GET',redirect:'manual',cache:'no-store',
    headers:{'accept':'text/html,application/javascript,text/javascript,application/manifest+json,application/json'},
    signal:AbortSignal.timeout(12000)
  });
  if(response.status!==200)throw new Error('HTTP '+response.status+
    (response.status>=300&&response.status<400?' (redirect rejected)':''));
  const expectedLength=Number(response.headers.get('content-length'));
  if(Number.isFinite(expectedLength)&&expectedLength>maxBytes)
    throw new Error('Public file exceeds size budget');
  const bytes=[];
  let total=0;
  for await(const chunk of response.body) {
    total+=chunk.length;
    if(total>maxBytes)throw new Error('Public file exceeds size budget');
    bytes.push(chunk);
  }
  return {body:Buffer.concat(bytes),type:response.headers.get('content-type')||''};
}
await mkdir(out,{recursive:true});
for(const file of FILES){
  try {
    const result=await readPublic(file.name,file.limit);
    const content=result.body.toString('utf8');
    if(file.expected==='json') {
      const json=JSON.parse(content);
      if(json.display!=='standalone'||typeof json.start_url!=='string'||
         typeof json.scope!=='string')
        throw new Error('App manifest lacks valid standalone/scope/start_url');
      const start=new URL(json.start_url,BASE+'/');
      const scope=new URL(json.scope,BASE+'/');
      if(start.origin!==BASE||scope.origin!==BASE)
        throw new Error('App manifest navigates outside production origin');
    } else if(file.expected==='js') {
      if(!content.includes('addEventListener')||!content.includes('fetch')||
         !content.includes('caches'))
        throw new Error('No recognisable offline service-worker fetch/cache logic');
      if(/caches\.match\(/.test(content))report.issues.push(
        'Service worker uses CacheStorage.match; cache order must be reviewed before claiming automatic updates.');
    } else if(file.expected==='html'&&!/<!doctype html|<html/i.test(content))
      throw new Error('Production root is not an HTML page');
    await writeFile(join(out,file.name),result.body);
    report.files.push({file:file.name,status:'HTTP 200',bytes:result.body.length,
      sha256:createHash('sha256').update(result.body).digest('hex'),
      contentType:result.type});
  } catch(error) {
    report.files.push({file:file.name,status:'unverified',error:error.message});
    report.issues.push(file.name+': '+error.message);
  }
}
report.accessible=report.files.every(x=>x.status==='HTTP 200');
report.actualIPhoneTested=false;
report.actualLiDARVerified=false;
report.updateDeliveryProved=false;
await writeFile(join(out,'LIVE_PRODUCTION_AUDIT.json'),
  JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({origin:BASE,accessible:report.accessible,
  files:report.files.map(x=>({file:x.file,status:x.status,bytes:x.bytes,error:x.error})),
  issues:report.issues},null,2));
if(!report.accessible)process.exitCode=1;
