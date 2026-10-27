// Ports the native GeometryPreview contract: ASCII XYZ PLY and triangle-only OBJ.
// Coordinates and original bytes are preserved. Only display geometry is normalized.
import { LIMITS } from './core.mjs';
export const GEOMETRY_LIMITS = { vertices: 200000, triangles: 60000, displayPoints: 20000 };
const bad = message => { throw new Error(message); };
const point = tokens => {
  if (tokens.length !== 3 || tokens.some(t => !/^[+-]?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?$/i.test(t))) bad('Ugyldige koordinater.');
  const p = tokens.map(Number);
  if (p.some(n => !Number.isFinite(n) || Math.abs(n) > 1000000)) bad('Koordinaterne er uden for visningens grænser.');
  return p;
};
export function parseGeometry(text, name) {
  if (new TextEncoder().encode(text).length > LIMITS.model) bad('3D-filen overstiger 8 MiB.');
  const ext = name.toLowerCase().split('.').pop();
  if (!['obj', 'ply'].includes(ext)) bad('Vælg Scan3D ASCII PLY eller trekantet OBJ uden materialer.');
  const lines = text.replace(/\r\n?/g, '\n').trim().split('\n').map(line => line.trim()).filter(Boolean);
  let vertices = [], faces = [];
  if (ext === 'ply') {
    if (lines[0] !== 'ply' || lines[1] !== 'format ascii 1.0') bad('Kun ASCII XYZ PLY understøttes.');
    let count, end = -1; const properties = [];
    for (let i = 2; i < Math.min(lines.length, 35); i++) {
      const line = lines[i], t = line.split(/\s+/);
      if (line === 'end_header') { end = i; break; }
      if (line.startsWith('comment ')) continue;
      if (t.length === 3 && t[0] === 'element' && t[1] === 'vertex' && count === undefined && /^\d+$/.test(t[2])) count = Number(t[2]);
      else if (t.length === 3 && t[0] === 'property' && t[1] === 'float' && count !== undefined) properties.push(t[2]);
      else bad('PLY skal kun indeholde XYZ-punkter uden ekstra elementer.');
    }
    if (end < 0 || !Number.isInteger(count) || count < 1 || count > GEOMETRY_LIMITS.vertices ||
        properties.join(',') !== 'x,y,z' || lines.length !== end + 1 + count) bad('Ugyldigt PLY-antal eller header.');
    vertices = lines.slice(end + 1).map(line => point(line.split(/\s+/)));
  } else {
    for (const line of lines) {
      const t = line.split(/\s+/);
      if (t[0].startsWith('#') || t[0] === 'o') continue;
      if (t[0] === 'v') {
        if (vertices.length >= GEOMETRY_LIMITS.vertices) bad('For mange 3D-punkter til webvisningen.');
        vertices.push(point(t.slice(1)));
      } else if (t[0] === 'f') {
        if (faces.length >= GEOMETRY_LIMITS.triangles || t.length !== 4 || !t.slice(1).every(n => /^[1-9]\d*$/.test(n))) bad('Kun trekantede OBJ-flader uden tekstur understøttes.');
        const f = t.slice(1).map(n => Number(n) - 1);
        if (!f.every(Number.isSafeInteger) || new Set(f).size !== 3) bad('Ugyldig OBJ-flade.');
        faces.push(f);
      } else bad('Materialer, teksturer og eksterne ressourcer understøttes ikke.');
    }
    if (!faces.length) bad('OBJ-filen mangler trekantede flader.');
    if (faces.some(f => f.some(i => i >= vertices.length))) bad('OBJ-fladen peger på et manglende punkt.');
    const used = new Map(), compact = [];
    faces = faces.map(face => face.map(i => {
      if (!used.has(i)) { used.set(i, compact.length); compact.push(vertices[i]); }
      return used.get(i);
    }));
    vertices = compact;
    for (const f of faces) {
      const a = vertices[f[0]], b = vertices[f[1]], c = vertices[f[2]];
      const u = b.map((n, i) => n - a[i]), v = c.map((n, i) => n - a[i]);
      if (Math.hypot(u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0]) === 0) bad('OBJ indeholder en flade uden areal.');
    }
  }
  const lo = [...vertices[0]], hi = [...vertices[0]];
  for (const p of vertices) for (let i = 0; i < 3; i++) { lo[i] = Math.min(lo[i], p[i]); hi[i] = Math.max(hi[i], p[i]); }
  const size = hi.map((n, i) => n - lo[i]), extent = Math.max(...size);
  if (extent <= 0.000001) bad('Modellen har ingen synlig udstrækning.');
  const center = hi.map((n, i) => (n + lo[i]) / 2);
  const normalized = vertices.map(p => p.map((n, i) => (n - center[i]) * 1.7 / extent));
  return { vertices, faces, normalized, size, isPointCloud: faces.length === 0 };
}
export function demoOBJ() {
  // Same synthetic vase profile as Scan3DLiDAR/Sources/StudioFixtures.swift.
  const profile = [[-.55,.18],[-.5,.28],[-.4,.33],[-.25,.34],[-.1,.30],[.05,.22],[.17,.15],[.32,.13],[.45,.13],[.48,.16]];
  const lines = ['# Scan3D SYNTHETIC DEMO; not a scan'];
  for (const [y,r] of profile) for (let i=0;i<48;i++) { const a=i*Math.PI*2/48; lines.push(`v ${1.2*r*Math.cos(a)} ${y+.035} ${.8*r*Math.sin(a)}`); }
  for (let row=0;row<profile.length-1;row++) for(let i=0;i<48;i++) { const a=row*48+i+1,b=row*48+(i+1)%48+1;lines.push(`f ${a} ${a+48} ${b}`,`f ${b} ${a+48} ${b+48}`); }
  return lines.join('\n')+'\n';
}
