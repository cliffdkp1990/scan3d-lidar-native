import test from 'node:test';import assert from 'node:assert/strict';
import {newProject,makeAsset,verifyAssets} from '../core.mjs';
import {serializeProject,deserializeProject} from '../store.mjs';
test('binary storage codec roundtrips actual bytes across structured clone',async()=>{
  const p=newProject('Binary model');p.model=await makeAsset(new Blob(['v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n'],{type:'text/plain'}),'model.obj',{origin:'import'});
  const encoded=await serializeProject(p);assert.ok(encoded.model.buffer instanceof ArrayBuffer);assert.equal(encoded.model.blob,undefined);
  const copy=deserializeProject(structuredClone(encoded));assert.equal(copy.id,p.id);assert.equal(copy.model.sha256,p.model.sha256);assert.equal(await copy.model.blob.text(),await p.model.blob.text());await verifyAssets(copy);
});
test('prior successful Blob records remain readable without mutation',()=>{const p=newProject('Existing');assert.equal(deserializeProject(p),p);assert.equal(p.storageEncoding,undefined);});
test('malformed stored buffers are rejected without modifying the record',()=>{const raw={...newProject(),storageEncoding:'array-buffer-v1',model:{buffer:'not binary'}};assert.throws(()=>deserializeProject(raw));assert.equal(raw.model.buffer,'not binary');});
