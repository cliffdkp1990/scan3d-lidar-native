// Data stays on this origin. No URLs, HTML or user-supplied object keys are executed.
import { VIDEO, videoType, checkVideo } from './video.mjs';
export const LIMITS = Object.freeze({ photos: 30, projects: 40, inputPhoto: 12 * 1024 ** 2,
  model: 8 * 1024 ** 2, project: 24 * 1024 ** 2, archive: 36 * 1024 ** 2 });
export const LEGACY_KEY = 'scan3d-safari-mvp-v1';
const PHOTO_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);
const fail = message => { throw new Error(message); };
export const uid = () => crypto.randomUUID();
export const cleanName = value => String(value || 'Mit projekt').replace(/[\u0000-\u001f\u007f]/g, '').trim().slice(0, 100) || 'Mit projekt';
export const safeFilename = value => cleanName(value).replace(/[<>:"/\\|?*]/g, '-');
export const sha256 = async blob => [...new Uint8Array(await crypto.subtle.digest('SHA-256', await blob.arrayBuffer()))]
  .map(n => n.toString(16).padStart(2, '0')).join('');
export async function checkRaster(blob) {
  const b=new Uint8Array(await blob.slice(0,12).arrayBuffer());
  const valid=blob.type==='image/jpeg'?b[0]===255&&b[1]===216&&b[2]===255:
    blob.type==='image/png'?[137,80,78,71,13,10,26,10].every((n,i)=>b[i]===n):
    blob.type==='image/webp'&&String.fromCharCode(...b.slice(0,4))==='RIFF'&&String.fromCharCode(...b.slice(8,12))==='WEBP';
  if(!valid)fail('Billedets faktiske filtype stemmer ikke. Vælg JPEG, PNG eller WebP.');
}
export function newProject(name = 'Min scanning') {
  const now = new Date().toISOString();
  return { version: 2, id: uid(), name: cleanName(name), revision: 0, createdAt: now, updatedAt: now, photos: [], videos: [], model: null };
}
export function validateProject(p) {
  if (!p || p.version !== 2 || !/^[a-zA-Z0-9-]{1,80}$/.test(p.id) || typeof p.name !== 'string' || p.name.length > 100 ||
      !Number.isSafeInteger(p.revision) || p.revision < 0 || !Number.isFinite(Date.parse(p.createdAt)) || !Number.isFinite(Date.parse(p.updatedAt)) ||
      !Array.isArray(p.photos) || p.photos.length > LIMITS.photos ||
      (p.videos !== undefined && (!Array.isArray(p.videos) || p.videos.length > VIDEO.count))) fail('Projektformatet er ugyldigt. Originalen er bevaret.');
  let total = 0;
  const ids = new Set();
  const videos = p.videos || [];
  for (const a of [...p.photos, ...videos, ...(p.model ? [p.model] : [])]) {
    if (!a || typeof a.id !== 'string' || ids.has(a.id) || !(a.blob instanceof Blob) || !/^[a-f0-9]{64}$/.test(a.sha256) ||
        typeof a.name !== 'string' || a.name.length > 100 || a.bytes !== a.blob.size || a.bytes <= 0) fail('Ugyldig projektfil. Originalen er bevaret.');
    ids.add(a.id); total += a.bytes;
    if (a === p.model) {
      if (!/\.(obj|ply)$/i.test(a.name) || a.bytes > LIMITS.model || !['demo', 'import'].includes(a.origin)) fail('Ugyldig 3D-fil.');
    } else if (videos.includes(a)) {
      if (!['video/mp4','video/webm'].includes(videoType(a.blob.type)) || a.bytes > VIDEO.bytes ||
          !Number.isInteger(a.width) || !Number.isInteger(a.height) || a.width < 1 || a.height < 1 ||
          Math.max(a.width,a.height) > 3840 || !Number.isFinite(a.duration) || a.duration <= 0 || a.duration > VIDEO.seconds + 0.5) fail('Ugyldig video.');
    } else if (!PHOTO_TYPES.has(a.blob.type) || a.bytes > LIMITS.inputPhoto || !Number.isInteger(a.width) || !Number.isInteger(a.height) ||
               a.width < 1 || a.height < 1 || a.width > 1600 || a.height > 1600) fail('Ugyldigt foto.');
  }
  if (total > LIMITS.project) fail('Projektet overstiger 24 MiB. Eksportér en kopi, før du tilføjer mere.');
  return p;
}
export async function verifyAssets(project) {
  validateProject(project);
  for (const a of [...project.photos, ...(project.videos || []), ...(project.model ? [project.model] : [])]) {
    if (await sha256(a.blob) !== a.sha256) fail('En gemt fil stemmer ikke med sin SHA-256. Originalen er bevaret.');
    if(project.photos.includes(a))await checkRaster(a.blob);
    else if(a!==project.model)await checkVideo(a.blob);
  }
}
export async function makeAsset(blob, name, extra = {}) {
  return { id: uid(), name: cleanName(name), bytes: blob.size, sha256: await sha256(blob), blob, ...extra };
}
export function encodeBase64(bytes) {
  const parts = [];
  for (let i = 0; i < bytes.length; i += 32768) parts.push(String.fromCharCode(...bytes.subarray(i, i + 32768)));
  return btoa(parts.join(''));
}
function decodeBase64(text, maxBytes) {
  if (typeof text !== 'string' || text.length > Math.ceil(maxBytes / 3) * 4 || text.length % 4 ||
      !/^[A-Za-z0-9+/]*={0,2}$/.test(text)) fail('Ugyldige binære data.');
  let decoded;try{decoded=atob(text);}catch{fail('Ugyldige binære data.');}
  if (!decoded.length || decoded.length > maxBytes) fail('Filens størrelse er ugyldig.');
  return Uint8Array.from(decoded, c => c.charCodeAt(0));
}
export async function exportArchive(project) {
  await verifyAssets(project);
  const encode = async a => ({ id: a.id, name: a.name, bytes: a.bytes, sha256: a.sha256, type: a.blob.type,
    width: a.width, height: a.height, duration: a.duration, origin: a.origin, data: encodeBase64(new Uint8Array(await a.blob.arrayBuffer())) });
  const photos = [];
  for (const a of project.photos) photos.push(await encode(a));
  const videos = []; for (const a of project.videos || []) videos.push(await encode(a));
  // Old readers must reject a video archive rather than silently drop its clips.
  const data = { format: 'scan3d-safari-project', version: videos.length ? 3 : 2, project: {
    name: project.name, createdAt: project.createdAt, updatedAt: project.updatedAt, photos,
    ...(videos.length ? {videos} : {}), model: project.model ? await encode(project.model) : null } };
  const blob = new Blob([JSON.stringify(data)], { type: 'application/json' });
  if (blob.size > LIMITS.archive) fail('Sikkerhedskopien er for stor.');
  return blob;
}
async function legacyProject(raw) {
  if (!raw || !Array.isArray(raw.photos) || raw.photos.length > LIMITS.photos) fail('Den gamle projektfil har ugyldige fotos.');
  const p = newProject(raw.name || 'Importeret projekt');
  let total=0;
  for (const value of raw.photos) {
    const match = typeof value === 'string' && value.match(/^data:(image\/(?:jpeg|png|webp));base64,([A-Za-z0-9+/=]+)$/);
    if (!match) fail('Den gamle projektfil indeholder en ikke-understøttet billedkilde.');
    const blob = new Blob([decodeBase64(match[2], LIMITS.inputPhoto)], { type: match[1] });
    total+=blob.size;if(total>LIMITS.project)fail('Det tidligere projekt overstiger 24 MiB. Originalen er bevaret.');
    // Dimensions are set by the browser after real image decoding, before saving.
    p.photos.push(await makeAsset(blob, 'Tidligere foto', { width: 1, height: 1, needsDecode: true }));
  }
  return validateProject(p);
}
export async function importArchive(text) {
  if (typeof text !== 'string' || new Blob([text]).size > LIMITS.archive) fail('Projektfilen overstiger 36 MiB.');
  let raw;
  try { raw = JSON.parse(text); } catch { fail('Filen er ikke gyldig JSON.'); }
  if (raw?.version === 1) return legacyProject(raw.project);
  if (raw?.format !== 'scan3d-safari-project' || ![2,3].includes(raw.version) || !raw.project ||
      !Array.isArray(raw.project.photos) || raw.project.photos.length > LIMITS.photos) fail('Ukendt projektformat.');
  if (raw.version === 3 && (!Array.isArray(raw.project.videos) || raw.project.videos.length > VIDEO.count) ||
      raw.version === 2 && raw.project.videos?.length) fail('Ugyldigt videoformat i sikkerhedskopien.');
  const p = newProject(raw.project.name);
  if(!Number.isFinite(Date.parse(raw.project.createdAt)))fail('Projektets oprettelsesdato er ugyldig.');
  p.createdAt=raw.project.createdAt;
  const decode = async (a, model, video = false) => {
    const limit = model ? LIMITS.model : video ? VIDEO.bytes : LIMITS.inputPhoto;
    if (!a || typeof a.name !== 'string' || typeof a.sha256 !== 'string' || !Number.isInteger(a.bytes) || a.bytes < 1 ||
        a.bytes > limit || (!model && !(video ? ['video/mp4','video/webm'].includes(videoType(a.type)) : PHOTO_TYPES.has(a.type)))) fail('Ugyldig fil i sikkerhedskopien.');
    const blob = new Blob([decodeBase64(a.data, limit)], { type: model ? 'text/plain' : a.type });
    if (blob.size !== a.bytes || await sha256(blob) !== a.sha256) fail('Sikkerhedskopiens filhash stemmer ikke.');
    if(video)await checkVideo(blob);else if(!model)await checkRaster(blob);
    return makeAsset(blob, a.name, model ? { origin: a.origin === 'demo' ? 'demo' : 'import' } : { width: a.width, height: a.height, ...(video ? {duration:a.duration} : {}) });
  };
  let total = 0;
  for (const a of raw.project.photos) {
    total += Number(a?.bytes) || LIMITS.project + 1;
    if (total > LIMITS.project) fail('Projektet overstiger 24 MiB.');
    p.photos.push(await decode(a, false));
  }
  for (const a of raw.version === 3 ? raw.project.videos : []) {
    total += Number(a?.bytes) || LIMITS.project + 1;
    if (total > LIMITS.project) fail('Projektet overstiger 24 MiB.');
    p.videos.push(await decode(a, false, true));
  }
  if (raw.project.model) p.model = await decode(raw.project.model, true);
  return validateProject(p);
}
export async function importLegacyList(text) {
  if (typeof text !== 'string' || new Blob([text]).size > LIMITS.archive) fail('Det tidligere lager er for stort til samlet import.');
  let list;
  try { list = JSON.parse(text); } catch { fail('Det tidligere lager er ugyldigt.'); }
  if (!Array.isArray(list) || !list.length || list.length > LIMITS.projects) fail('Det tidligere projektantal er ugyldigt.');
  const result = [];
  for (const p of list) result.push(await legacyProject(p));
  return result;
}
