import test from 'node:test';
import assert from 'node:assert/strict';
import { parseGeometry } from '../geometry.mjs';
import { validatePrintableMesh, exportBinarySTL } from '../stl.mjs';
const tetra = ['v 0 0 0','v 1 0 0','v 0 1 0','v 0 0 1','f 1 3 2','f 1 2 4','f 2 3 4','f 3 1 4'].join('\n');
test('closed tetrahedron exports a binary STL with original coordinates',async()=>{
  const g=parseGeometry(tetra,'tetra.obj');
  assert.equal(validatePrintableMesh(g).triangles,4);
  const bytes=await exportBinarySTL(g).arrayBuffer(),view=new DataView(bytes);
  assert.equal(bytes.byteLength,84+4*50);
  assert.equal(view.getUint32(80,true),4);
  assert.equal(view.getFloat32(84+12,true),0);
});
test('rejects point cloud',()=>assert.throws(()=>exportBinarySTL(parseGeometry('ply\nformat ascii 1.0\nelement vertex 2\nproperty float x\nproperty float y\nproperty float z\nend_header\n0 0 0\n1 0 0\n','cloud.ply')),/Punktskyer/));
test('rejects open mesh',()=>assert.throws(()=>exportBinarySTL(parseGeometry('v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3','open.obj')),/lukket/));
test('rejects inconsistent face orientation',()=>{
 const g=parseGeometry(tetra,'tetra.obj');
 g.faces[0]=[...g.faces[0]].reverse();
 assert.throws(()=>exportBinarySTL(g),/orienteret/);
});
test('rejects non-manifold edge',()=>{
 const g=parseGeometry(tetra,'tetra.obj');
 g.faces.push([...g.faces[0]]);
 assert.throws(()=>exportBinarySTL(g),/ikke-manifold/);
});
