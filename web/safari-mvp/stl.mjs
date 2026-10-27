// Export only closed, consistently oriented triangle meshes. Never reconstruct a point cloud.
import { triangleNormal, GEOMETRY_LIMITS } from './geometry.mjs';
export function validatePrintableMesh(geometry) {
  if (!geometry || geometry.isPointCloud || !Array.isArray(geometry.faces) || !geometry.faces.length)
    throw new Error('Punktskyer kan ikke eksporteres som STL uden mesh-rekonstruktion.');
  const { vertices, faces } = geometry;
  if (vertices.length > GEOMETRY_LIMITS.vertices || faces.length > GEOMETRY_LIMITS.triangles)
    throw new Error('Modellen overskrider eksportgrænserne.');
  const edges = new Map();
  let signedVolume6 = 0;
  for (const face of faces) {
    if (!Array.isArray(face) || face.length !== 3 || new Set(face).size !== 3 ||
        face.some(i => !Number.isSafeInteger(i) || i < 0 || i >= vertices.length))
      throw new Error('Ugyldige trekantindekser.');
    const [a,b,c] = face.map(i => vertices[i]);
    if ([a,b,c].some(p => !Array.isArray(p) || p.length !== 3 || p.some(v => !Number.isFinite(v))))
      throw new Error('Ugyldige 3D-koordinater.');
    triangleNormal(a,b,c);
    signedVolume6 += a[0]*(b[1]*c[2]-b[2]*c[1]) + a[1]*(b[2]*c[0]-b[0]*c[2]) + a[2]*(b[0]*c[1]-b[1]*c[0]);
    for (const [u,v] of [[face[0],face[1]],[face[1],face[2]],[face[2],face[0]]]) {
      const key = Math.min(u,v)+':'+Math.max(u,v);
      const state = edges.get(key) || {count:0,orientation:0};
      state.count++; state.orientation += u<v ? 1 : -1; edges.set(key,state);
    }
  }
  if ([...edges.values()].some(e => e.count !== 2 || e.orientation !== 0))
    throw new Error('STL kræver en lukket, orienteret overflade uden åbne eller ikke-manifold kanter.');
  if (!Number.isFinite(signedVolume6) || Math.abs(signedVolume6) < 1e-12)
    throw new Error('Modellen har intet målbart lukket volumen.');
  return { triangles:faces.length, signedVolume:signedVolume6/6 };
}
export function exportBinarySTL(geometry) {
  validatePrintableMesh(geometry);
  const { vertices, faces } = geometry;
  const buffer = new ArrayBuffer(84 + faces.length*50);
  const view = new DataView(buffer);
  const header = new TextEncoder().encode('Scan3D Safari validated mesh; original coordinate units; verify scale before printing');
  new Uint8Array(buffer,0,Math.min(80,header.length)).set(header.slice(0,80));
  view.setUint32(80,faces.length,true);
  let offset=84;
  for (const face of faces) {
    const [a,b,c]=face.map(i=>vertices[i]),normal=triangleNormal(a,b,c);
    for (const value of [...normal,...a,...b,...c]) {view.setFloat32(offset,value,true);offset+=4;}
    view.setUint16(offset,0,true);offset+=2;
  }
  return new Blob([buffer],{type:'model/stl'});
}
