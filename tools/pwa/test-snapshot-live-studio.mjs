#!/usr/bin/env node
// Offline safety tests, using the exact public worker already captured by CI.
import assert from 'node:assert/strict';
import {readFile,mkdir,mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {ORIGIN,SOURCE_SHA,parseStaticAssets,backup} from './snapshot-live-studio.mjs';

const auditDir=process.argv[2];
if(!auditDir)throw new Error('Pass the verified production audit directory');
const raw=await readFile(join(auditDir,'sw.js'),'utf8');
assert.equal(createHash('sha256').update(raw).digest('hex'),SOURCE_SHA);
const files=parseStaticAssets(raw);
assert.equal(files.size,28,'All 27 unique original assets plus the worker itself are required');
assert(files.has('studio.html'));assert(files.has('index.html'));
assert(files.has('assets/scanbot_demo.glb'));
assert(files.has('assets/scanbot_demo.stl'));
assert(files.has('atelier.js'));assert(files.has('sw.js'));
assert([...files].every(([name,url])=>url===ORIGIN+'/'+name));

for(const altered of [
  raw+' ',
  raw.replace("'./studio.html'","'https://attacker.invalid/'"),
  raw.replace("'./studio.html'","'./../private.txt'"),
  raw.replace("'./studio.html'","'./studio.html?access=1'"),
  raw.replace("'./studio.html'","'./app.js'"),
  ''
]){
  assert.throws(()=>parseStaticAssets(altered),'Stale or modified public SW cannot be accepted');
}

const temp=await mkdtemp(join(tmpdir(),'scan3d-public-source-'));
try{
  const fixture=join(temp,'fixture');
  const dest=join(temp,'verified');
  await mkdir(fixture);
  await writeFile(join(fixture,'sw.js'),raw);
  await writeFile(join(fixture,'LIVE_PRODUCTION_AUDIT.json'),JSON.stringify({
    origin:ORIGIN,accessible:true,files:[
      {file:'sw.js',status:'HTTP 200',sha256:SOURCE_SHA},
      {file:'manifest.webmanifest',status:'HTTP 200'}
    ]
  }));
  const manifest={
    id:'./',display:'standalone',start_url:'./index.html',scope:'./'
  };
  const requests=[];
  const retrieveFile=async url=>{
    requests.push(url);
    const file=url.slice((ORIGIN+'/').length);
    return {
      bytes:file==='sw.js'?Buffer.from(raw):
        file==='manifest.webmanifest'?Buffer.from(JSON.stringify(manifest)):
        Buffer.from('public static fixture: '+file),
      contentType:'test/fixture'
    };
  };
  const receipt=await backup(fixture,dest,{retrieveFile});
  assert.equal(receipt.filesVerified,29);
  assert.equal(receipt.referenceWorkerSHA256,SOURCE_SHA);
  assert.deepEqual(receipt.originalAppIdentity,{
    id:'./',start_url:'./index.html',scope:'./'
  });
  assert.equal(receipt.containsUserScans,false);
  assert.equal(receipt.containsPrivateFiles,false);
  assert.equal(receipt.containsVercelBuildConfig,true);
  assert.equal(receipt.isCompleteDeploymentSource,false);
  assert.equal(receipt.readyForDeployment,false);
  assert.equal(receipt.writeToProduction,false);
  assert.equal(requests.length,28); // all non-worker assets + one consistency check
  assert(requests.every(url=>url.startsWith(ORIGIN+'/')));
  const original=await readFile(join(dest,'original-public-source','sw.js'),'utf8');
  assert.equal(original,raw);
  const saved=JSON.parse(await readFile(join(dest,'PUBLIC_SOURCE_RECEIPT.json'),'utf8'));
  assert.equal(saved.files.length,29);
  assert.equal(saved.files.find(x=>x.file==='sw.js').sha256,SOURCE_SHA);
  const vercel=JSON.parse(await readFile(join(dest,'original-public-source','vercel.json'),'utf8'));
  assert.equal(vercel.headers.find(x=>x.source==='/sw.js').headers[0].value,'no-cache');
  assert(!saved.files.some(x=>x.file.includes('projects')||x.file.includes('secret')));
  await assert.rejects(()=>backup(fixture,dest,{retrieveFile}),
    /EEXIST|file already exists/i,'Never overwrite the original backup');
  const changed=async url=>({
    bytes:url===ORIGIN+'/sw.js'?Buffer.from(raw+'changed'):
      Buffer.from(url.endsWith('manifest.webmanifest')?JSON.stringify(manifest):'fixture'),
    contentType:'test/fixture'
  });
  await assert.rejects(()=>backup(fixture,join(temp,'changed'),{retrieveFile:changed}),
    /Production worker changed/,'A mid-job live deployment must invalidate the snapshot');
  const broken=JSON.parse(await readFile(join(fixture,'LIVE_PRODUCTION_AUDIT.json'),'utf8'));
  broken.files[0].sha256='0'.repeat(64);
  await writeFile(join(fixture,'LIVE_PRODUCTION_AUDIT.json'),JSON.stringify(broken));
  await assert.rejects(()=>backup(fixture,join(temp,'broken'),{retrieveFile}),
    /Untrusted or changed/, 'Stale audit must fail closed');
  console.log('Scan3D: 28 public assets plus exact Vercel config, no login, no project data, app identity, source immutability, full SHA receipt and failure gates: PASS');
}finally{
  await rm(temp,{recursive:true,force:true});
}
