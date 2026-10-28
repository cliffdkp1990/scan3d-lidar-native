import {test,expect} from '@playwright/test';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
const photo=fileURLToPath(new URL('./fixtures/photo.png',import.meta.url));
const movie=fileURLToPath(new URL('./fixtures/synthetic-rgbd.mp4',import.meta.url));
const obj='v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n';
const pageErrors=new WeakMap();
test.beforeEach(async({page})=>{const errors=[];pageErrors.set(page,errors);page.on('pageerror',e=>errors.push(e.message));});
test.afterEach(async({page})=>{expect(pageErrors.get(page)).toEqual([]);});
async function ready(page,url='/'){await page.goto(url);await expect(page.locator('body')).toHaveAttribute('data-ready','true');await expect(page.locator('#new-project')).toBeEnabled();}
async function saved(page){await expect(page.locator('#save-state')).toHaveAttribute('data-saved','true');await expect(page.locator('#new-project')).toBeEnabled();}
async function create(page,name='QA projekt'){await page.locator('#new-project').click();await saved(page);await page.locator('#project-name').fill(name);await page.locator('#save-project').click();await saved(page);}
async function addPhoto(page){await page.locator('#photo-file').setInputFiles(photo);await expect(page.locator('#photo-count')).toHaveText('1');await saved(page);}
async function addModel(page,text=obj,name='native.obj'){await page.locator('#model-file').setInputFiles({name,mimeType:'text/plain',buffer:Buffer.from(text)});await expect(page.locator('#export-model')).toBeVisible();await saved(page);}
async function download(page,selector){const event=page.waitForEvent('download');await page.locator(selector).click();const d=await event;expect(await d.failure()).toBeNull();return readFile(await d.path());}
test('save, reload, reopen and enlarge real project photos',async({page})=>{
  await ready(page);await create(page,'QA fotos');await addPhoto(page);await create(page,'QA andet');await page.reload();await saved(page);
  await page.locator('#open-library').click();await page.getByRole('button',{name:/QA fotos/}).click();
  await expect(page.locator('#library')).not.toBeVisible();await expect(page.locator('#photo-count')).toHaveText('1');
  await page.getByRole('button',{name:'Åbn foto 1',exact:true}).click();await expect(page.locator('#photo-dialog')).toBeVisible();
  await expect.poll(()=>page.locator('#full-photo').evaluate(e=>e.naturalWidth)).toBe(128);
  const image=await download(page,'#download-photo');expect([...image.subarray(0,3)]).toEqual([255,216,255]);
  await page.keyboard.press('Escape');await expect(page.locator('#photo-dialog')).not.toBeVisible();
});
test('real 3D renderer, rotate, zoom, reset and synthetic labelling',async({page},info)=>{
  await ready(page);await page.locator('#model-tab').click();await page.locator('#demo-model').click();await saved(page);
  await expect(page.locator('#model-canvas')).toHaveAttribute('data-state','ready');await expect(page.locator('#model-canvas')).toHaveAttribute('data-triangles','864');
  await expect(page.locator('#model-kind')).toHaveText('Syntetisk demo');
  const before=await page.locator('#model-canvas').getAttribute('data-yaw');await page.getByRole('button',{name:'Drej modellen til højre',exact:true}).click();await expect(page.locator('#model-canvas')).not.toHaveAttribute('data-yaw',before);
  await page.getByRole('button',{name:'Zoom ind',exact:true}).click();await expect(page.locator('#model-canvas')).toHaveAttribute('data-zoom','1.200');
  await page.getByRole('button',{name:'Nulstil',exact:true}).click();await expect(page.locator('#model-canvas')).toHaveAttribute('data-zoom','1.000');
  await page.locator('#model-panel').screenshot({path:info.outputPath('actual-model.png')});
});
test('native OBJ export is byte-exact; invalid external materials cannot replace it',async({page})=>{
  const external=[];page.on('request',r=>{if(!r.url().startsWith('http://127.0.0.1:4173')&&!r.url().startsWith('blob:'))external.push(r.url());});
  await ready(page);await create(page,'QA model');await addModel(page);expect((await download(page,'#export-model')).toString()).toBe(obj);
  await page.locator('#model-file').setInputFiles({name:'bad.obj',mimeType:'text/plain',buffer:Buffer.from('mtllib https://example.com/evil.mtl\n'+obj)});
  await expect(page.locator('#status')).toHaveAttribute('data-error','true');await expect(page.locator('#project-count')).toHaveText('1');
  expect((await download(page,'#export-model')).toString()).toBe(obj);expect(external).toEqual([]);
});
test('STL download is permitted for a closed tetrahedron and rejected for an open mesh',async({page})=>{
  const tetra=['v 0 0 0','v 1 0 0','v 0 1 0','v 0 0 1','f 1 3 2','f 1 2 4','f 2 3 4','f 3 1 4'].join('\n')+'\n';
  await ready(page);await create(page,'STL validering');await addModel(page);
  await expect(page.locator('#export-stl')).toBeHidden();
  await addModel(page,tetra,'lukket.obj');
  await expect(page.locator('#export-stl')).toBeVisible();
  const bytes=await download(page,'#export-stl');
  expect(bytes.byteLength).toBe(84+4*50);
  expect(bytes.readUInt32LE(80)).toBe(4);
  expect(bytes.readFloatLE(84+12+12+4)).toBe(1);
  await expect(page.locator('#status')).toContainText('Kontrollér enheder');
  await page.reload();await saved(page);await page.locator('#model-tab').click();
  await expect(page.locator('#export-stl')).toBeVisible();
});
test('new models preserve the previous saved model in a separate project',async({page})=>{
  await ready(page);await create(page,'QA original');await addModel(page);await addModel(page,obj.replace('v 1 0 0','v 2 0 0'),'new.obj');
  await expect(page.locator('#project-count')).toHaveText('2');await page.locator('#open-library').click();await page.getByRole('button',{name:/QA original 0 fotos/}).click();await saved(page);
  expect((await download(page,'#export-model')).toString()).toBe(obj);
});
test('project download/import preserves file hashes and rejects corrupted backup',async({page})=>{
  await ready(page);await create(page,'QA backup');await addPhoto(page);await addModel(page);await page.locator('#prepare-export').click();await expect(page.locator('#download-backup')).toBeVisible();
  const bytes=await download(page,'#download-backup'),raw=JSON.parse(bytes);expect(raw.version).toBe(2);expect(raw.project.photos).toHaveLength(1);
  for(const a of [...raw.project.photos,raw.project.model])expect(createHash('sha256').update(Buffer.from(a.data,'base64')).digest('hex')).toBe(a.sha256);
  await page.locator('#import-file').setInputFiles({name:'backup.json',mimeType:'application/json',buffer:bytes});await expect(page.locator('#project-count')).toHaveText('2');await saved(page);
  raw.project.model.data='QUJDRA==';await page.locator('#import-file').setInputFiles({name:'corrupt.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(raw))});await expect(page.locator('#status')).toHaveAttribute('data-error','true');await expect(page.locator('#project-count')).toHaveText('2');
});
test('legacy storage migration is atomic, idempotent and non-destructive',async({page})=>{
  const text=JSON.stringify([{id:'old',name:'QA gammel',photos:['data:image/png;base64,'+(await readFile(photo)).toString('base64')]}]);
  await page.addInitScript(value=>localStorage.setItem('scan3d-safari-mvp-v1',value),text);await ready(page);await page.locator('#import-legacy').click();await expect(page.locator('#project-count')).toHaveText('1');await saved(page);
  expect(await page.evaluate(()=>localStorage.getItem('scan3d-safari-mvp-v1'))).toBe(text);
  await page.locator('#import-legacy').click();await expect(page.locator('#status')).toContainText('allerede importeret');await expect(page.locator('#project-count')).toHaveText('1');
});
test('camera permission denial keeps file-photo capture available',async({page})=>{
  await ready(page,'/?qa=camera-denied');await create(page);await page.locator('#start-camera').click();await expect(page.locator('#status')).toContainText('afvist');await expect(page.locator('#camera-state')).toHaveText('Kamera slukket');await addPhoto(page);
});
test('synthetic live camera captures a photo and releases tracks on pagehide',async({page},info)=>{
  await ready(page);test.skip(!await page.evaluate(()=>typeof document.createElement('canvas').captureStream==='function'),'Windows WebKit lacks canvas.captureStream; not a physical camera test.');
  await ready(page,'/?qa=camera-fake');await create(page);await page.locator('#start-camera').click();await expect(page.locator('#camera-state')).toHaveText('Live · uden lyd');
  await expect.poll(()=>page.locator('#camera').evaluate(v=>v.readyState)).toBeGreaterThanOrEqual(2);
  await page.locator('#take-photo').click();await expect(page.locator('#photo-count')).toHaveText('1');await saved(page);
  await page.locator('#photo-panel').screenshot({path:info.outputPath('synthetic-camera.png')});
  await page.evaluate(()=>window.dispatchEvent(new PageTransitionEvent('pagehide')));await expect(page.locator('#camera-state')).toHaveText('Kamera slukket');
  expect(await page.locator('#camera').evaluate(v=>v.srcObject)).toBeNull();
});

async function canDecodeMovie(page) {
  return page.evaluate(async()=>{const video=document.createElement('video'),blob=await(await fetch('./tests/fixtures/synthetic-rgbd.mp4')).blob(),url=URL.createObjectURL(blob);video.muted=true;video.preload='auto';
    return new Promise(resolve=>{const timer=setTimeout(()=>finish(false),3000);const finish=value=>{clearTimeout(timer);video.onloadeddata=video.onerror=null;video.removeAttribute('src');video.load();URL.revokeObjectURL(url);resolve(value);};video.onloadeddata=()=>finish(true);video.onerror=()=>finish(false);video.src=url;video.load();});
  });
}
test('blocked storage preserves a visible draft that can still be exported',async({page})=>{
  await ready(page,'/?qa=storage-denied');await page.locator('#new-project').click();await expect(page.locator('#save-state')).toContainText('Kladde');
  await page.locator('#photo-file').setInputFiles(photo);await expect(page.locator('#photo-count')).toHaveText('1');await expect(page.locator('#save-state')).toHaveAttribute('data-saved','false');
  await page.locator('#prepare-export').click();await expect(page.locator('#download-backup')).toBeVisible();const raw=JSON.parse(await download(page,'#download-backup'));expect(raw.project.photos).toHaveLength(1);
});
test('aborted write keeps previous database data and current unsaved draft',async({page,context})=>{
  await ready(page);await create(page,'QA atomisk');await addPhoto(page);
  await page.evaluate(()=>{const put=IDBObjectStore.prototype.put;IDBObjectStore.prototype.put=function(value,...args){const request=put.call(this,value,...args);if(this.name==='projects'&&value.photos?.length===2)this.transaction.abort();return request;};});
  await page.locator('#photo-file').setInputFiles(photo);await expect(page.locator('#photo-count')).toHaveText('2');await expect(page.locator('#save-state')).toHaveAttribute('data-saved','false');
  const other=await context.newPage();await ready(other);await expect(other.locator('#photo-count')).toHaveText('1');await other.close();
});
test('cross-tab updates cannot silently overwrite another revision',async({page,context})=>{
  await ready(page);await create(page,'QA konflikt');const other=await context.newPage();await ready(other);
  await other.locator('#project-name').fill('QA anden fane');await other.locator('#save-project').click();await saved(other);
  await page.locator('#photo-file').setInputFiles(photo);await expect(page.locator('#status')).toContainText('anden fane');await expect(page.locator('#save-state')).toHaveAttribute('data-saved','false');
  await other.reload();await saved(other);await expect(other.locator('#project-name')).toHaveValue('QA anden fane');await expect(other.locator('#photo-count')).toHaveText('0');await other.close();
});
test('unavailable WebGL still permits original-model export',async({page})=>{
  await ready(page,'/?qa=no-webgl');await create(page);await addModel(page);await expect(page.locator('#model-empty')).toContainText('ikke tilgængelig');await expect(page.getByRole('button',{name:'Zoom ind',exact:true})).toBeDisabled();expect((await download(page,'#export-model')).toString()).toBe(obj);
});
test('22px text and all three layouts retain 44px controls without horizontal overflow',async({page},info)=>{
  await ready(page);await page.evaluate(()=>document.documentElement.style.fontSize='22px');await page.locator('#model-tab').click();await page.locator('#demo-model').click();await saved(page);await expect(page.locator('#model-canvas')).toHaveAttribute('data-state','ready');
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  for(const b of await page.locator('#model-panel button:visible').all()){const box=await b.boundingBox();expect(box.height).toBeGreaterThanOrEqual(44);expect(box.x).toBeGreaterThanOrEqual(0);expect(box.x+box.width).toBeLessThanOrEqual(page.viewportSize().width);}
  await page.screenshot({path:info.outputPath('layout-22px.png'),fullPage:true});
});

test('video import roundtrips exact bytes or preserves the file on a real codec rejection',async({page})=>{
  await ready(page);const decodes=await canDecodeMovie(page);await create(page,'QA video');await addPhoto(page);
  if(!decodes){await page.locator('#video-file').setInputFiles(movie);await expect(page.locator('#status')).toContainText('codec',{timeout:12000});await expect(page.locator('#recover-video')).toBeVisible();expect(await download(page,'#recover-video')).toEqual(await readFile(movie));await expect(page.locator('#video-count')).toHaveText('0');await expect(page.locator('#photo-count')).toHaveText('1');await saved(page);return;}
  await page.locator('#video-file').setInputFiles(movie);await expect(page.locator('#video-count')).toHaveText('1');await saved(page);
  const video=page.locator('#videos video');await video.evaluate(v=>v.play());await expect.poll(()=>video.evaluate(v=>v.currentTime)).toBeGreaterThan(0);await video.evaluate(v=>v.pause());
  expect(await download(page,'#videos a')).toEqual(await readFile(movie));
  await page.reload();await saved(page);await expect(page.locator('#video-count')).toHaveText('1');
  await page.locator('#prepare-export').click();const backup=await download(page,'#download-backup'),raw=JSON.parse(backup);
  expect(raw.version).toBe(3);expect(raw.project.videos).toHaveLength(1);expect(raw.project.photos).toHaveLength(1);
  expect(createHash('sha256').update(Buffer.from(raw.project.videos[0].data,'base64')).digest('hex')).toBe(raw.project.videos[0].sha256);
  await page.locator('#import-file').setInputFiles({name:'video.json',mimeType:'application/json',buffer:backup});await expect(page.locator('#project-count')).toHaveText('2');await saved(page);
  raw.project.videos[0].data='QUJDRA==';await page.locator('#import-file').setInputFiles({name:'bad.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(raw))});
  await expect(page.locator('#status')).toHaveAttribute('data-error','true');await expect(page.locator('#project-count')).toHaveText('2');await expect(page.locator('#video-count')).toHaveText('1');
  for(let i=0;i<2;i++){await page.locator('#video-file').setInputFiles(movie);await expect(page.locator('#video-count')).toHaveText(String(i+2));await saved(page);}
  await page.locator('#video-file').setInputFiles(movie);await expect(page.locator('#status')).toContainText('Højst tre');await expect(page.locator('#video-count')).toHaveText('3');
});
test('missing recorder leaves file-video import available',async({page})=>{
  await page.addInitScript(()=>Object.defineProperty(window,'MediaRecorder',{value:undefined,configurable:true}));await ready(page);await create(page);
  await expect(page.locator('#start-video')).toBeDisabled();await expect(page.locator('#choose-video')).toBeEnabled();
  if(await canDecodeMovie(page)){await page.locator('#video-file').setInputFiles(movie);await expect(page.locator('#video-count')).toHaveText('1');await saved(page);}
  else {await page.locator('#video-file').setInputFiles(movie);await expect(page.locator('#status')).toContainText('codec',{timeout:12000});await expect(page.locator('#recover-video')).toBeVisible();expect(await download(page,'#recover-video')).toEqual(await readFile(movie));await expect(page.locator('#video-count')).toHaveText('0');await saved(page);}
});
test('recording capabilities either finalize a real synthetic stream or retain the import controls',async({page},info)=>{
  await ready(page);
  const supported=await page.evaluate(()=>typeof MediaRecorder==='function'&&typeof document.createElement('canvas').captureStream==='function');
  if(!supported){await create(page,'QA uden optagelse');await expect(page.locator('#choose-video')).toBeEnabled();await expect(page.locator('#stop-video')).toBeHidden();await expect(page.locator('#new-project')).toBeEnabled();if(!await page.evaluate(()=>typeof MediaRecorder==='function')){await expect(page.locator('#start-video')).toBeDisabled();await expect(page.locator('#video-state')).toContainText('kan ikke optage');}return;}
  await ready(page,'/?qa=camera-fake');await create(page,'QA optagelse');await page.locator('#start-camera').click();await expect(page.locator('#camera-state')).toHaveText('Live · uden lyd');
  await page.locator('#start-video').click();await expect(page.locator('#video-state')).toContainText('Optager');await expect(page.locator('#new-project')).toBeDisabled();await expect(page.locator('#model-tab')).toBeDisabled();
  await page.waitForTimeout(1200);await page.locator('#stop-video').click();await expect(page.locator('#video-count')).toHaveText('1');await saved(page);
  await page.locator('#videos video').evaluate(v=>v.play());await expect.poll(()=>page.locator('#videos video').evaluate(v=>v.currentTime)).toBeGreaterThan(0);
  await page.locator('#videos video').evaluate(v=>v.pause());await page.locator('#photo-panel').screenshot({path:info.outputPath('actual-synthetic-video.png')});
  await page.locator('#start-video').click();await page.waitForTimeout(600);await page.evaluate(()=>window.dispatchEvent(new PageTransitionEvent('pagehide')));
  await expect(page.locator('#camera-state')).toHaveText('Kamera slukket');await expect(page.locator('#video-count')).toHaveText('2');await saved(page);
  await page.reload();await saved(page);await expect(page.locator('#video-count')).toHaveText('2');
});

test('home-screen metadata and app icons load, with honest Chrome iPhone instructions',async({page})=>{
  await page.addInitScript(()=>{Object.defineProperty(navigator,'userAgent',{value:'iPhone CriOS/155 Safari/604.1',configurable:true});});
  await ready(page);const response=await page.request.get('/manifest.webmanifest');expect(response.ok()).toBe(true);expect(response.headers()['content-type']).toContain('application/manifest+json');const manifest=await response.json();expect(manifest.display).toBe('standalone');expect(manifest.start_url).toBe('./');
  for(const icon of manifest.icons){const r=await page.request.get('/'+icon.src.replace('./',''));expect(r.ok()).toBe(true);expect(r.headers()['content-type']).toContain('image/png');}
  await page.locator('#install-app').click();await expect(page.locator('#install-dialog')).toBeVisible();await expect(page.locator('#install-instructions')).toContainText('I Chrome på iPhone');await expect(page.locator('#install-instructions')).toContainText('Del');await expect(page.locator('#native-install')).toBeHidden();await expect(page.locator('#install-dialog')).toContainText('Projekter i en anden browser');await page.locator('#close-install').click();
  expect(await page.locator('#new-project').evaluate(b=>getComputedStyle(b).userSelect)).toBe('none');expect(await page.locator('#project-name').evaluate(b=>getComputedStyle(b).userSelect)).toBe('text');
});
test('Safari iPhone home-screen help never asks for ZIP, login or native app signing',async({page})=>{
  await page.addInitScript(()=>{Object.defineProperty(navigator,'userAgent',{value:'iPhone Version/27 Safari/604.1',configurable:true});});
  await ready(page);
  await expect(page.locator('#pwa-update')).toBeHidden();
  await page.locator('#install-app').click();
  await expect(page.locator('#install-instructions')).toContainText('I Safari på iPhone');
  await expect(page.locator('#install-instructions')).toContainText('Føj til hjemmeskærm');
  await expect(page.locator('#install-instructions')).toContainText('Ingen ZIP');
  await page.locator('#close-install').click();
  await page.locator('#camera-help').click();
  await expect(page.locator('#permission-guide')).toContainText('Safari');
  await page.locator('#close-permissions').click();
});
test('camera help reads permissions without requesting them and recovers from a denied request',async({page})=>{
  await page.addInitScript(()=>{window.qaCameraCalls=0;Object.defineProperty(navigator,'mediaDevices',{configurable:true,value:{getUserMedia:async()=>{window.qaCameraCalls++;throw new DOMException('test denial','NotAllowedError');}}});Object.defineProperty(navigator,'permissions',{configurable:true,value:{query:async()=>({state:'denied'})}});});
  await ready(page);await page.locator('#camera-help').click();await expect(page.locator('#permission-results')).toContainText('Blokeret');expect(await page.evaluate(()=>window.qaCameraCalls)).toBe(0);await expect(page.locator('#permission-note')).toContainText('ingen mikrofon');await page.locator('#close-permissions').click();
  await create(page);await page.locator('#start-camera').click();await expect(page.locator('#camera-help')).toContainText('Kamera blokeret');expect(await page.evaluate(()=>window.qaCameraCalls)).toBe(1);await expect(page.locator('#choose-photo')).toBeEnabled();await page.locator('#camera-help').click();await expect(page.locator('#permission-dialog')).toBeVisible();await page.locator('#check-permissions').click();expect(await page.evaluate(()=>window.qaCameraCalls)).toBe(1);
});

test('guided capture creates one project, persists its choice and preserves photos when switching',async({page})=>{
  await page.addInitScript(()=>{window.guideCameraCalls=0;Object.defineProperty(navigator,'mediaDevices',{configurable:true,value:{getUserMedia:async()=>{window.guideCameraCalls++;throw new DOMException('test','NotAllowedError');}}});});
  await ready(page);await expect(page.locator('#capture-steps')).toBeHidden();
  await page.getByRole('button',{name:'Vælg vejledning til et rum',exact:true}).click();await saved(page);
  await expect(page.locator('#project-count')).toHaveText('1');await expect(page.locator('#project-name')).toHaveValue('Mit rum');
  await expect(page.locator('[data-capture-mode="room"]')).toHaveAttribute('aria-pressed','true');
  await expect(page.locator('#start-camera')).toBeFocused();
  expect(await page.evaluate(()=>window.guideCameraCalls)).toBe(0);
  await addPhoto(page);await expect(page.locator('#capture-summary')).toHaveText('1 foto · 0 videoer · ingen 3D-model endnu');
  await page.getByRole('button',{name:'Vælg vejledning til en genstand',exact:true}).click();
  await expect(page.locator('#project-count')).toHaveText('1');await expect(page.locator('#project-name')).toHaveValue('Mit rum');
  await expect(page.locator('#photo-count')).toHaveText('1');
  await page.reload();await saved(page);await expect(page.locator('[data-capture-mode="object"]')).toHaveAttribute('aria-pressed','true');
  await page.locator('#capture-step-title').click();await expect(page.locator('#capture-step-list li')).toHaveCount(3);
  await page.evaluate(()=>document.documentElement.style.fontSize='200%');
  const overflow=()=>page.evaluate(()=>({width:innerWidth,documentWidth:document.documentElement.scrollWidth,elements:[...document.querySelectorAll('main *')].map(e=>{const r=e.getBoundingClientRect();return {tag:e.tagName,id:e.id,width:r.width,right:r.right};}).filter(r=>r.width>0&&r.right>innerWidth+1).slice(0,8)}));
  let layout=await overflow();expect(layout.documentWidth,JSON.stringify(layout)).toBeLessThanOrEqual(layout.width+1);
  await page.evaluate(()=>document.documentElement.style.fontFamily='Verdana,sans-serif');
  layout=await overflow();expect(layout.documentWidth,JSON.stringify(layout)).toBeLessThanOrEqual(layout.width+1);
  for(const button of await page.locator('[data-capture-mode]').all()){const box=await button.boundingBox();expect(box.width).toBeGreaterThanOrEqual(44);expect(box.height).toBeGreaterThanOrEqual(44);}
  await page.locator('#prepare-export').click();const backup=JSON.parse(await download(page,'#download-backup'));
  expect(backup.version).toBe(2);expect(backup.project.photos).toHaveLength(1);expect(backup.project.model).toBeNull();
  expect(createHash('sha256').update(Buffer.from(backup.project.photos[0].data,'base64')).digest('hex')).toBe(backup.project.photos[0].sha256);
});

test('guide storage failure and project storage failure retain an honest usable draft',async({page})=>{
  await page.addInitScript(()=>{const get=Storage.prototype.getItem,set=Storage.prototype.setItem;Storage.prototype.getItem=function(key){if(key==='scan3d-capture-guide-v1')throw new DOMException('test','SecurityError');return get.call(this,key);};Storage.prototype.setItem=function(key,value){if(key==='scan3d-capture-guide-v1')throw new DOMException('test','QuotaExceededError');return set.call(this,key,value);};});
  await ready(page,'/?qa=storage-denied');
  await page.getByRole('button',{name:'Vælg vejledning til en genstand',exact:true}).click();
  await expect(page.locator('#save-state')).toHaveAttribute('data-saved','false');
  await expect(page.locator('#status')).toHaveAttribute('data-error','true');
  await expect(page.locator('#capture-storage-note')).toBeVisible();
  await expect(page.locator('#capture-next')).toContainText('endnu ikke gemt');
  await page.locator('#photo-file').setInputFiles(photo);await expect(page.locator('#photo-count')).toHaveText('1');
  await page.locator('#prepare-export').click();const backup=JSON.parse(await download(page,'#download-backup'));expect(backup.project.photos).toHaveLength(1);
  await page.reload();await expect(page.locator('body')).toHaveAttribute('data-ready','true');
  await expect(page.locator('#project-count')).toHaveText('0');await expect(page.locator('[data-capture-mode="object"]')).toHaveAttribute('aria-pressed','false');
});
