import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { LIMITS, newProject, validateProject, verifyAssets, makeAsset, exportArchive, importArchive, importLegacyList, encodeBase64, checkRaster } from '../core.mjs';
const png=await readFile(new URL('./fixtures/photo.png',import.meta.url));
async function project(){const p=newProject('<b>Mit projekt</b>');p.photos.push(await makeAsset(new Blob([png],{type:'image/png'}),'foto.png',{width:128,height:96}));p.model=await makeAsset(new Blob(['v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n'],{type:'text/plain'}),'test.obj',{origin:'import'});return p;}
test('archive roundtrip preserves photo/model bytes, hashes and creation date; always a new ID',async()=>{
  const p=await project(),bytes=await exportArchive(p),copy=await importArchive(await bytes.text());
  assert.notEqual(copy.id,p.id);assert.equal(copy.createdAt,p.createdAt);assert.equal(copy.name,p.name);assert.equal(copy.revision,0);
  assert.deepEqual(new Uint8Array(await copy.photos[0].blob.arrayBuffer()),new Uint8Array(png));
  assert.equal(await copy.model.blob.text(),await p.model.blob.text());await verifyAssets(copy);
});
test('corrupted archived bytes cannot be accepted by copying a hash field',async()=>{
  const raw=JSON.parse(await (await exportArchive(await project())).text());raw.project.photos[0].data='QUJDRA==';await assert.rejects(importArchive(JSON.stringify(raw)),/hash|filhash/);
});
test('unknown versions and malformed JSON are rejected',async()=>{await assert.rejects(importArchive('{'));await assert.rejects(importArchive('{"version":99}'));});
test('remote photo URLs and SVG cannot enter legacy data',async()=>{
  for(const photo of ['https://example.com/photo.png','data:image/svg+xml;base64,PHN2Zz4=','javascript:alert(1)'])await assert.rejects(importArchive(JSON.stringify({version:1,project:{photos:[photo]}})));
});
test('legacy export and original project list remain readable without mutating input',async()=>{
  const old={name:'Første projekt',photos:['data:image/png;base64,'+encodeBase64(png)]},text=JSON.stringify([old]);
  const list=await importLegacyList(text);assert.equal(list.length,1);assert.equal(list[0].photos[0].needsDecode,true);assert.equal(JSON.stringify([old]),text);
  const p=await importArchive(JSON.stringify({version:1,project:old}));assert.equal(p.name,old.name);assert.equal(p.photos[0].bytes,png.length);
});
test('archive photo-count bound applies before decoding',async()=>{await assert.rejects(importArchive(JSON.stringify({version:1,project:{photos:Array(LIMITS.photos+1).fill('bad')}})));});
test('integrity verification detects altered saved blobs',async()=>{const p=await project();p.model.blob=new Blob(['bad']);p.model.bytes=3;await assert.rejects(verifyAssets(p),/SHA-256/);});
test('duplicate asset IDs and project resource overrun are rejected',async()=>{
  const p=await project();p.photos.push(p.photos[0]);assert.throws(()=>validateProject(p),/Ugyldig/);
  const q=newProject(),blob=new Blob([new Uint8Array(1024**2)],{type:'image/png'});
  q.photos=Array.from({length:25},(_,i)=>({id:String(i),name:'p',blob,bytes:blob.size,width:1,height:1,sha256:'a'.repeat(64)}));assert.throws(()=>validateProject(q),/24 MiB/);
});
test('a valid hash does not make disguised SVG an accepted raster',async()=>{await assert.rejects(checkRaster(new Blob(['<svg onload="alert(1)"></svg>'],{type:'image/png'})),/filtype/);});
test('noncanonical/oversized base64 and invalid dates are rejected',async()=>{
  const raw=JSON.parse(await (await exportArchive(await project())).text());raw.project.photos[0].data='%%%%';await assert.rejects(importArchive(JSON.stringify(raw)));
  raw.project.createdAt='bad date';await assert.rejects(importArchive(JSON.stringify(raw)),/dato/);
});
