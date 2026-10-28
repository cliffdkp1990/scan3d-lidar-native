import { LIMITS, validateProject } from './core.mjs';
// Finish binary serialization before starting an IndexedDB transaction.
export async function serializeProject(project) {
  const encode=async asset=>{const{blob,...metadata}=asset;return{...metadata,type:blob.type,buffer:await blob.arrayBuffer()};};
  const photos=[];for(const asset of project.photos)photos.push(await encode(asset));
  const videos=[];for(const asset of project.videos||[])videos.push(await encode(asset));
  return{...project,storageEncoding:'array-buffer-v1',photos,videos,model:project.model?await encode(project.model):null};
}
export function deserializeProject(record) {
  if(record.storageEncoding!=='array-buffer-v1')return record;
  const decode=asset=>{const{buffer,type,...metadata}=asset;if(!(buffer instanceof ArrayBuffer))throw new Error('Ugyldig lagret binær fil.');return{...metadata,blob:new Blob([buffer],{type})};};
  const{storageEncoding,...metadata}=record;
  return{...metadata,photos:record.photos.map(decode),videos:record.videos===undefined?[]:record.videos.map(decode),model:record.model?decode(record.model):null};
}
export class ProjectStore {
  constructor(indexedDB) {
    try { this.indexedDB = arguments.length ? indexedDB : globalThis.indexedDB; } catch { this.indexedDB = null; }
    this.db = null;
  }
  async open() {
    if (this.db) return this.db;
    if (!this.indexedDB) throw new Error('Lokalt lager er ikke tilgængeligt. Bevar fanen, og eksportér en sikkerhedskopi.');
    return new Promise((resolve, reject) => {
      let settled = false;
      const request = this.indexedDB.open('scan3d-safari-projects-v2', 1);
      const timer = setTimeout(() => finish(new Error('Lokalt lager svarede ikke. Luk andre Scan3D-faner, og prøv igen.')), 8000);
      const finish = (error, db) => {
        if (settled) { db?.close(); return; }
        settled = true; clearTimeout(timer);
        if (error) reject(error); else { this.db = db; db.onversionchange = () => { db.close(); this.db = null; }; resolve(db); }
      };
      request.onupgradeneeded = () => { request.result.createObjectStore('projects', { keyPath: 'id' }); request.result.createObjectStore('meta', { keyPath: 'id' }); };
      request.onerror = () => finish(new Error('Lokalt lager er blokeret. Bevar fanen, og eksportér dit projekt.'));
      request.onblocked = () => finish(new Error('En anden fane blokerer lageret. Luk den, og prøv igen.'));
      request.onsuccess = () => finish(null, request.result);
    });
  }
  async list() {
    const db = await this.open();
    return new Promise((resolve, reject) => {
      const transaction = db.transaction('projects', 'readonly'), request = transaction.objectStore('projects').getAll();
      let rows;
      request.onsuccess = () => { rows = request.result.map(row=>{try{return deserializeProject(row);}catch{return{...row,version:-1};}}); };
      transaction.oncomplete = () => resolve(rows.sort((a,b) => String(b.updatedAt).localeCompare(String(a.updatedAt))));
      transaction.onerror = transaction.onabort = () => reject(new Error('Gemte projekter kunne ikke læses. Data er bevaret.'));
    });
  }
  async save(project) {
    validateProject(project);
    const db = await this.open();
    const next = { ...project, revision: project.revision + 1, updatedAt: new Date().toISOString() };
    const record = await serializeProject(next);
    return new Promise((resolve, reject) => {
      const transaction = db.transaction('projects', 'readwrite'), store = transaction.objectStore('projects');
      let error;
      const current = store.get(project.id);
      current.onsuccess = () => {
        if ((current.result?.revision || 0) !== project.revision) {
          error = new Error('Projektet er ændret i en anden fane. Eksportér din kladde, før du genåbner den gemte version.');
          transaction.abort(); return;
        }
        if (!current.result) {
          const count = store.count();
          count.onsuccess = () => {
            if (count.result >= LIMITS.projects) { error = new Error('Der er allerede 40 projekter i lageret. Din kladde kan eksporteres.'); transaction.abort(); }
            else store.put(record);
          };
        } else store.put(record);
      };
      transaction.oncomplete = () => resolve(next);
      transaction.onabort = transaction.onerror = () => reject(error || new Error('Projektet blev ikke gemt. Lageret kan være fuldt eller blokeret. Eksportér kladden.'));
    });
  }
  async importLegacy(projects, migrationId) {
    projects.forEach(validateProject);
    const db = await this.open();
    const next = projects.map(p => ({ ...p, revision: 1 })),records=[];
    for(const p of next)records.push(await serializeProject(p));
    return new Promise((resolve, reject) => {
      const transaction = db.transaction(['projects', 'meta'], 'readwrite');
      const store = transaction.objectStore('projects'), meta = transaction.objectStore('meta');
      let error;
      const marker = meta.get(migrationId);
      marker.onsuccess = () => {
        if (marker.result) { error = new Error('Disse tidligere projekter er allerede importeret.'); transaction.abort(); return; }
        const count = store.count();
        count.onsuccess = () => {
          if (count.result + next.length > LIMITS.projects) { error = new Error('Importen overskrider grænsen på 40 projekter. Det tidligere lager er bevaret.'); transaction.abort(); return; }
          records.forEach(p => store.add(p)); meta.put({ id: migrationId });
        };
      };
      transaction.oncomplete = () => resolve(next);
      transaction.onerror = transaction.onabort = () => reject(error || new Error('Importen blev rullet tilbage. Det tidligere lager er bevaret.'));
    });
  }
}
