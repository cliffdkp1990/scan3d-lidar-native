import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {importArchive,verifyAssets,exportArchive} from '../../web/safari-mvp/core.mjs';
import {parseGeometry} from '../../web/safari-mvp/geometry.mjs';
const dir=process.env.BRIDGE_FIXTURE_DIR;
assert.ok(dir,'BRIDGE_FIXTURE_DIR must contain output from the actual Swift exporter');
for(const ext of ['ply','obj']) {
  const original=await readFile(resolve(dir,'original.'+ext));
  const native=await readFile(resolve(dir,'native-'+ext+'.scan3d.json'),'utf8');
  const project=await importArchive(native);
  await verifyAssets(project);
  assert.deepEqual(Buffer.from(await project.model.blob.arrayBuffer()),original);
  assert.equal(project.photos.length,0);
  const model=parseGeometry(await project.model.blob.text(),project.model.name);
  assert.equal(model.vertices.length,3);
  assert.equal(model.faces.length,ext==='obj'?1:0);
  assert.equal(model.isPointCloud,ext==='ply');
  const copy=await importArchive(await (await exportArchive(project)).text());
  assert.deepEqual(Buffer.from(await copy.model.blob.arrayBuffer()),original);
  assert.notEqual(copy.id,project.id);
  const broken=JSON.parse(native);broken.project.model.sha256='0'.repeat(64);
  await assert.rejects(importArchive(JSON.stringify(broken)),/filhash/);
}
const demo=await importArchive(await readFile(resolve(dir,'synthetic.scan3d.json'),'utf8'));
assert.equal(demo.model.origin,'demo');
console.log('Native Swift → actual Safari importer → backup → reimport: PLY/OBJ passed; bytes and hashes match. Synthetic fixtures only.');
