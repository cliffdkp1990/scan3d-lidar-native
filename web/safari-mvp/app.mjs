import { LIMITS, LEGACY_KEY, cleanName, safeFilename, newProject, validateProject, verifyAssets, makeAsset, sha256, checkRaster, exportArchive, importArchive, importLegacyList } from './core.mjs';
import { ProjectStore } from './store.mjs';
import { CameraSession, decodePhoto, jpegCopy } from './camera.mjs';
import { parseGeometry, demoOBJ } from './geometry.mjs';
import { validatePrintableMesh, exportBinarySTL } from './stl.mjs';
import { ModelViewer } from './viewer.mjs';
import { Record3DSession } from './record3d-session.mjs';
import { VIDEO, VideoRecorder, decodeVideo, videoType } from './video.mjs';
import { initLaunchHelp } from './launch.mjs';
import { initPWAUpdates, canSwitchPWA } from './pwa-updates.mjs';
import { CaptureGuide } from './capture-guide.mjs';
import { PLANS, validMode } from './capture-guide-core.mjs';

const $ = selector => document.querySelector(selector);
const captureGuide = new CaptureGuide($('#capture-guide'));
const store = new ProjectStore();
let active = null, projects = [], dirty = false, busy = true, cameraState = 'stopped', modelId = null;
let photoURLs = [], modelURL = null, stlGeometry = null, backupURL = null, backupFile = null, dialogURL = null;
let recording = false, videoURLs = [], recoveryURL = null, videoClock = null;
let pwaUpdates = null;
const delayedURLs = new Set();
const status = (message, error = false) => { $('#status').textContent = message; $('#status').dataset.error = String(error); };
const delayedRevoke = url => { if (url) { delayedURLs.add(url); setTimeout(() => { URL.revokeObjectURL(url); delayedURLs.delete(url); }, 30000); } };
let viewer;
const depth=new Record3DSession($('#rgbd-video'),(state,message)=>{
  $('#rgbd-state').textContent=message;$('#rgbd-state').dataset.state=state;
  $('#rgbd-video').hidden=state==='stopped';controls();
});
try { viewer = new ModelViewer($('#model-canvas'), message => { $('#model-info').textContent = message; }); }
catch { viewer = { gl: null, clear() {}, setGeometry() {}, action() {} }; $('#model-info').textContent = '3D-grafikken kunne ikke startes. Originale filer kan stadig eksporteres.'; }
const camera = new CameraSession($('#camera'), navigator.mediaDevices, state => {
  if (state === 'stopped' && recording) videoRecorder.stop();
  cameraState = state;
  $('#camera-state').textContent = { stopped: 'Kamera slukket', pending: 'Afventer tilladelse', active: 'Live · uden lyd' }[state];
  $('#camera').hidden = state === 'stopped'; $('#camera-placeholder').hidden = state !== 'stopped'; controls();
});
const videoRecorder = new VideoRecorder({ onState: state => {
  $('#stop-video').disabled = state !== 'recording';
  if (state === 'stopping') $('#video-state').textContent = 'Afslutter og gemmer video…';
} });
function controls() {
  const locked = busy || recording;
  captureGuide.render(active, locked, dirty);
  for (const id of ['new-project','choose-import','import-legacy','open-library','demo-model']) $('#'+id).disabled = locked;
  for (const id of ['save-project','choose-photo','choose-model','prepare-export','choose-video']) $('#'+id).disabled = locked || !active;
  $('#choose-video').disabled ||= (active?.videos || []).length >= VIDEO.count;
  $('#project-name').disabled = locked || !active; $('#capture-file').disabled = locked || !active;
  $('#start-camera').disabled = locked || !active || cameraState !== 'stopped';
  $('#take-photo').disabled = locked || !active || cameraState !== 'active';
  $('#start-video').disabled = locked || !active || cameraState !== 'active' || !videoRecorder.supported || (active.videos || []).length >= VIDEO.count;
  $('#stop-video').hidden = !recording;
  $('#photo-tab').disabled = recording; $('#model-tab').disabled = recording;
  $('#stop-camera').hidden = cameraState === 'stopped'; $('#stop-camera').disabled = false;
  $('#connect-depth').disabled=locked||depth.state!=='stopped';
  $('#depth-address').disabled=depth.state!=='stopped';
  $('#capture-depth').disabled=locked||depth.state!=='live';
  $('#stop-depth').disabled=depth.state==='stopped';
  document.querySelectorAll('[data-view]').forEach(b => { b.disabled = busy || !active?.model || !viewer.gl; });
  $('#save-state').textContent = !active ? 'Intet projekt valgt' : dirty ? 'Kladde · endnu ikke gemt. Bevar fanen eller eksportér.' : 'Gemt lokalt · revision '+active.revision;
  $('#save-state').dataset.saved = String(Boolean(active && !dirty));
  pwaUpdates?.refresh();
}
function clearBackup() {
  delayedRevoke(backupURL); backupURL = null; backupFile = null;
  $('#download-backup').hidden = true; $('#download-backup').removeAttribute('href'); $('#share-backup').hidden = true;
}
function showTab(name, focus = false) {
  if (recording) return;
  if (name === 'model') camera.stop();
  for (const kind of ['photo','model']) {
    const selected = name === kind;
    $('#'+kind+'-tab').setAttribute('aria-selected', String(selected)); $('#'+kind+'-tab').tabIndex = selected ? 0 : -1;
    $('#'+kind+'-panel').hidden = !selected;
  }
  if (focus) $('#'+name+'-tab').focus();
  if (name === 'model') viewer.schedule?.();
}
function library() {
  $('#project-count').textContent = projects.length;
  const root = $('#projects'); root.replaceChildren();
  if (!projects.length) { const p=document.createElement('p');p.textContent='Dine gemte projekter vises her. Opret et projekt for at begynde.';root.append(p); }
  for (const project of projects) {
    const button=document.createElement('button');button.className='project-card';button.dataset.projectId=project.id;
    const text=document.createElement('span'),title=document.createElement('strong'),meta=document.createElement('small'),symbol=document.createElement('span');
    title.textContent=project.name;meta.textContent=project.photos.length+' fotos · '+(project.videos?.length ? project.videos.length+' videoer · ' : '')+(project.model?'3D-model':'ingen 3D-model');
    text.append(title,meta);symbol.textContent=project.model?'◇':'▧';symbol.className='project-symbol';symbol.setAttribute('aria-hidden','true');button.append(text,symbol);
    button.addEventListener('click',()=>perform(async()=>{ await flush();await refreshLibrary();const selected=projects.find(p=>p.id===project.id);if(!selected)throw new Error('Projektet kunne ikke genåbnes. Originalen er bevaret.');await verifyAssets(selected);if(selected.model)parseGeometry(await selected.model.blob.text(),selected.model.name);active=selected;dirty=false;camera.stop();clearBackup();render();$('#library').close();showTab(selected.model?'model':'photo',true);status('Projektet er genåbnet fra lokalt lager.'); }));
    root.append(button);
  }
}
function renderVideos() {
  const root = $('#videos'); root.querySelectorAll('video').forEach(v => { v.pause(); v.removeAttribute('src'); v.load(); });
  videoURLs.forEach(URL.revokeObjectURL); videoURLs = []; root.replaceChildren();
  $('#video-count').textContent = active?.videos?.length || 0;
  for (const [i, asset] of (active?.videos || []).entries()) {
    const card = document.createElement('article'), video = document.createElement('video'), link = document.createElement('a'), caption = document.createElement('p');
    const url = URL.createObjectURL(asset.blob); videoURLs.push(url);
    card.className = 'video-card'; video.controls = true; video.playsInline = true; video.preload = 'metadata'; video.src = url;
    video.setAttribute('aria-label', 'Projektvideo ' + (i + 1));
    caption.textContent = 'Klip '+(i+1)+' · '+asset.duration.toFixed(1)+' sek. · '+(asset.bytes / 1024 / 1024).toFixed(1)+' MiB';
    video.addEventListener('error', () => { caption.textContent = 'Browseren kan ikke afspille dette klip. Download og sikkerhedskopi er stadig tilgængelige.'; });
    link.className = 'button'; link.href = url; link.download = safeFilename(asset.name); link.textContent = 'Hent video '+(i+1);
    card.append(video, caption, link); root.append(card);
  }
}
function renderPhotos() {
  photoURLs.forEach(URL.revokeObjectURL);photoURLs=[];const root=$('#photos');root.replaceChildren();$('#photo-count').textContent=active?.photos.length||0;
  if (!active?.photos.length) { const p=document.createElement('p');p.className='empty-text';p.textContent=active?'Tag et foto eller vælg et fra Fotos eller Filer.':'Opret eller åbn et projekt for at begynde.';root.append(p); }
  for (const [i,photo] of (active?.photos||[]).entries()) {
    const url=URL.createObjectURL(photo.blob);photoURLs.push(url);const button=document.createElement('button'),image=document.createElement('img'),caption=document.createElement('span');
    button.className='photo-card';button.setAttribute('aria-label','Åbn foto '+(i+1));image.src=url;image.alt='Projektfoto '+(i+1);image.loading='lazy';caption.textContent=(i+1)+' · '+photo.width+' × '+photo.height;
    image.addEventListener('error',()=>{caption.textContent='Foto kunne ikke vises. Originalkopien er bevaret.';});
    button.append(image,caption);button.addEventListener('click',()=>{
      delayedRevoke(dialogURL);dialogURL=URL.createObjectURL(photo.blob);$('#full-photo').src=dialogURL;$('#download-photo').href=dialogURL;$('#download-photo').download=safeFilename(photo.name)+'.jpg';$('#photo-title').textContent='Foto '+(i+1);$('#photo-dialog').showModal();
    });root.append(button);
  }
}
function renderModel() {
  const asset=active?.model;
  if ((asset?.id||null)===modelId) return;
  modelId=asset?.id||null;stlGeometry=null;$('#export-stl').hidden=true;viewer.clear();delayedRevoke(modelURL);modelURL=null;$('#export-model').hidden=true;
  $('#model-empty').hidden=Boolean(asset&&viewer.gl);$('#model-kind').textContent='Ingen model';
  $('#model-empty').textContent=asset&&!viewer.gl?'3D-grafik er ikke tilgængelig. Originalen kan stadig eksporteres.':'Åbn din model. Eller prøv en syntetisk vase.';
  if (!asset) { $('#model-info').textContent='Originale filer bevares. Modeller er ikke rekonstruktioner af dine fotos.';return; }
  const selectedId=asset.id;
  asset.blob.text().then(text=>{
    if(active?.model?.id!==selectedId)return;
    const geometry=parseGeometry(text,asset.name);
    modelURL=URL.createObjectURL(asset.blob);$('#export-model').href=modelURL;$('#export-model').download=safeFilename(asset.name);$('#export-model').hidden=false;
    viewer.setGeometry(geometry);
    try { validatePrintableMesh(geometry); stlGeometry=geometry; $('#export-stl').hidden=false; }
    catch { stlGeometry=null; $('#export-stl').hidden=true; }
    $('#model-kind').textContent=asset.origin==='demo'?'Syntetisk demo':geometry.isPointCloud?'Importeret punktsky':'Importeret mesh';
    $('#model-info').textContent=geometry.vertices.length.toLocaleString('da-DK')+' punkter · '+geometry.faces.length.toLocaleString('da-DK')+' trekanter. '+(geometry.isPointCloud?'Viser højst 20.000 punkter. ':'')+'Filens egne enheder; ingen kalibreret opmåling.'+(viewer.gl?'':' WebGL mangler; originalen kan eksporteres.');
    controls();
  }).catch(error=>{if(active?.model?.id===selectedId){$('#model-empty').hidden=false;$('#model-empty').textContent='Modellen kunne ikke vises.';status(error.message,true);}});
}
function render() { $('#project-name').value=active?.name||'';renderPhotos();renderVideos();renderModel();library();controls(); }
async function refreshLibrary() {
  const values=await store.list(),valid=[];let invalid=0;
  for(const p of values){try{validateProject(p);valid.push(p);}catch{invalid++;}}
  projects=valid;library();if(invalid)status(invalid+' projekt(er) kunne ikke læses. De originale lagerposter er bevaret.',true);
}
async function flush() {
  if(!active||!dirty)return;
  active=await store.save({...active,name:cleanName(active.name)});dirty=false;await refreshLibrary();controls();
}
async function commit(next) {
  validateProject(next);active=next;dirty=true;clearBackup();render();
  try{await flush();status('Projektet er gemt lokalt.');}catch(error){status(error.message,true);controls();}
}
async function perform(fn) {
  if(busy || recording)return;busy=true;controls();
  try{await fn();}catch(error){const message=error?.message||'Handlingen kunne ikke gennemføres. Dine filer er bevaret.';status(message,true);if($('#library').open)$('#library-note').textContent=message;}
  finally{busy=false;controls();}
}
async function importedPhotos(project) {
  const result=[];
  for(const asset of project.photos){
    await checkRaster(asset.blob);
    const image=await decodePhoto(asset.blob);
    if(asset.needsDecode){const copy=await jpegCopy(image,image.naturalWidth,image.naturalHeight);result.push(await makeAsset(copy.blob,asset.name,{width:copy.width,height:copy.height}));}
    else{if(image.naturalWidth!==asset.width||image.naturalHeight!==asset.height)throw new Error('Fotoets faktiske størrelse stemmer ikke med sikkerhedskopien.');result.push(asset);}
  }
  for (const asset of project.videos || []) {
    const metadata = await decodeVideo(asset.blob, asset.duration);
    if (metadata.width !== asset.width || metadata.height !== asset.height)
      throw new Error('Videoens størrelse stemmer ikke med sikkerhedskopien.');
  }
  const next={...project,photos:result};if(next.model)parseGeometry(await next.model.blob.text(),next.model.name);return validateProject(next);
}
async function addVideo(blob, name, seconds) {
  if (!active) throw new Error('Opret eller åbn et projekt først.');
  if ((active.videos || []).length >= VIDEO.count) throw new Error('Højst tre videoer pr. projekt. Opret et nyt projekt.');
  // Keep an independent download available if decoding, project budget or storage fails.
  delayedRevoke(recoveryURL); recoveryURL = URL.createObjectURL(blob);
  $('#recover-video').href = recoveryURL; $('#recover-video').download = safeFilename(name); $('#recover-video').hidden = false;
  const metadata = await decodeVideo(blob, seconds), asset = await makeAsset(blob, name, metadata);
  await commit({...active, videos: [...(active.videos || []), asset]});
  if (!dirty) { $('#recover-video').hidden = true; delayedRevoke(recoveryURL); recoveryURL = null; }
}
$('#start-video').addEventListener('click', async () => {
  if (busy || recording || !active || (active.videos || []).length >= VIDEO.count) return;
  recording = true; controls(); const started = performance.now();
  $('#video-state').textContent = 'Optager · 0 / 30 sek. · uden lyd';
  videoClock = setInterval(() => { if (videoRecorder.state === 'recording') $('#video-state').textContent = 'Optager · '+Math.min(30,Math.floor((performance.now()-started)/1000))+' / 30 sek. · uden lyd'; }, 250);
  try {
    const {blob, duration} = await videoRecorder.start(camera.stream);
    clearInterval(videoClock); recording = false;
    await perform(() => addVideo(blob, 'Kameravideo-'+new Date().toISOString().replace(/[:.]/g,'-')+(videoType(blob.type)==='video/mp4'?'.mp4':'.webm'), duration));
  } catch (error) { status(error.message, true); }
  finally { clearInterval(videoClock); recording = false; $('#video-state').textContent = 'Optagelsen er afsluttet. Se klippet eller statusmeddelelsen.'; controls(); }
});
$('#stop-video').addEventListener('click', () => videoRecorder.stop());
$('#choose-video').addEventListener('click', () => $('#video-file').click());
$('#video-file').addEventListener('change', event => { const file=event.target.files?.[0];event.target.value='';if(file)perform(()=>addVideo(file,file.name)); });
async function addPhoto(blob,name,source) {
  if(!active)throw new Error('Opret eller åbn et projekt først.');
  if(active.photos.length>=LIMITS.photos)throw new Error('Projektet har allerede 30 fotos. Eksportér en kopi, og opret et nyt projekt.');
  let copy;
  if(source==='camera'){
    const video=$('#camera');if(video.readyState<2||!video.videoWidth)throw new Error('Kamerabilledet er ikke klar endnu.');
    copy=await jpegCopy(video,video.videoWidth,video.videoHeight);
  }else{
    if(!blob||blob.size>LIMITS.inputPhoto||!['image/jpeg','image/png','image/webp'].includes(blob.type))throw new Error('Vælg JPEG, PNG eller WebP under 12 MiB. HEIC skal først konverteres eller optages med livekameraet.');
    await checkRaster(blob);const image=await decodePhoto(blob);copy=await jpegCopy(image,image.naturalWidth,image.naturalHeight);
  }
  const asset=await makeAsset(copy.blob,name,{width:copy.width,height:copy.height});await commit({...active,photos:[...active.photos,asset]});
}
$('#new-project').addEventListener('click',()=>perform(async()=>{await flush();camera.stop();await commit(newProject('Projekt '+new Date().toLocaleString('da-DK',{day:'2-digit',month:'short',hour:'2-digit',minute:'2-digit'})));showTab('photo');$('#project-name').focus();$('#project-name').select();}));
for (const button of document.querySelectorAll('[data-capture-mode]')) button.addEventListener('click',async()=>{await perform(async()=>{
  const mode = button.dataset.captureMode; if (!validMode(mode)) return;
  if (!active) await commit(newProject(PLANS[mode].name));
  captureGuide.select(active.id, mode); captureGuide.render(active, true, dirty);
  showTab('photo'); status(dirty ? 'Projektet er en kladde. Gem en sikkerhedskopi, hvis lageret ikke kan bruges.' : 'Vejledningen er valgt. Kameraet er slukket.', dirty);
});if(button.getAttribute('aria-pressed')==='true')$('#start-camera').focus();});
$('#project-name').addEventListener('input',()=>{if(active){active={...active,name:$('#project-name').value};dirty=true;clearBackup();controls();}});
$('#save-project').addEventListener('click',()=>perform(async()=>{await flush();render();status('Projektet er gemt lokalt.');}));
$('#start-camera').addEventListener('click',async()=>{try{if(await camera.start())status('Kameraet er aktivt uden lyd. Vælg Tag foto eller Optag video.');}catch(error){status(error.message,true);window.dispatchEvent(new Event('scan3d:cameraerror'));}});
$('#stop-camera').addEventListener('click',()=>{const wasRecording=recording;videoRecorder.stop();camera.stop();if(!wasRecording)status('Kameraet er slukket.');});
$('#connect-depth').addEventListener('click',async()=>{
  camera.stop();try{await depth.start($('#depth-address').value.trim(),{encodingConfirmed:$('#depth-encoding').checked});}catch(error){status(error.message,true);}
});
$('#stop-depth').addEventListener('click',()=>depth.stop());
$('#capture-depth').addEventListener('click',()=>perform(async()=>{
  const text=depth.snapshot();parseGeometry(text,'Record3D-RGBD.ply');await flush();
  const model=await makeAsset(new Blob([text],{type:'text/plain'}),'Record3D-RGBD.ply',{origin:'import'});
  await commit({...newProject('Record3D RGBD · '+new Date().toLocaleString('da-DK')),model});
  showTab('model',true);if(!dirty)status('RGBD-dybdeudsnit gemt som nyt projekt. Sensor ikke bekræftet; ingen fusion eller kalibreret opmåling.');
}));
$('#take-photo').addEventListener('click',()=>perform(()=>addPhoto(null,'Kamerafoto '+new Date().toLocaleTimeString('da-DK'),'camera')));
$('#choose-photo').addEventListener('click',()=>$('#photo-file').click());
for(const id of ['photo-file','capture-file'])$('#'+id).addEventListener('change',event=>{const file=event.target.files?.[0];event.target.value='';if(file)perform(()=>addPhoto(file,file.name,'file'));});
$('#choose-model').addEventListener('click',()=>$('#model-file').click());
$('#model-file').addEventListener('change',event=>{const file=event.target.files?.[0];event.target.value='';if(file)perform(async()=>{
  if(!active)throw new Error('Opret eller åbn et projekt først.');
  if(file.size>LIMITS.model)throw new Error('3D-filen overstiger 8 MiB.');
  parseGeometry(await file.text(),file.name);const asset=await makeAsset(file,file.name,{origin:'import'});
  let project=active;
  if(active.model){await flush();project={...newProject(active.name+' · ny model'),photos:active.photos,videos:active.videos||[]};}
  await commit({...project,model:asset});showTab('model',true);
});});
$('#export-stl').addEventListener('click',()=>perform(async()=>{
  if(!active?.model || !stlGeometry)throw new Error('Kun validerede, lukkede trekantmodeller kan eksporteres som STL.');
  const blob=exportBinarySTL(stlGeometry);
  const url=URL.createObjectURL(blob), link=document.createElement('a');
  link.href=url;link.download=safeFilename(active.model.name.replace(/\.obj$/i,''))+'.stl';
  document.body.append(link);link.click();link.remove();delayedRevoke(url);
  status('STL klargjort. Kontrollér enheder, mål og printbarhed i sliceren før 3D-print.');
}));
$('#demo-model').addEventListener('click',()=>perform(async()=>{await flush();const p=newProject('Syntetisk 3D-demo');const asset=await makeAsset(new Blob([demoOBJ()],{type:'text/plain'}),'Demo-vase.obj',{origin:'demo'});await commit({...p,model:asset});showTab('model',true);}));
document.querySelectorAll('[data-view]').forEach(button=>button.addEventListener('click',()=>viewer.action(button.dataset.view)));
for(const kind of ['photo','model']){
  const tab=$('#'+kind+'-tab');tab.addEventListener('click',()=>showTab(kind));
  tab.addEventListener('keydown',event=>{if(!event.ctrlKey&&!event.metaKey&&!event.altKey&&['ArrowLeft','ArrowRight','Home','End'].includes(event.key)){event.preventDefault();showTab(event.key==='Home'?'photo':event.key==='End'?'model':kind==='photo'?'model':'photo',true);}});
}
$('#open-library').addEventListener('click',()=>{camera.stop();$('#library-note').textContent='';$('#library').showModal();});
$('#close-library').addEventListener('click',()=>$('#library').close());
$('#close-photo').addEventListener('click',()=>$('#photo-dialog').close());
$('#photo-dialog').addEventListener('close',()=>{delayedRevoke(dialogURL);dialogURL=null;$('#full-photo').removeAttribute('src');});
$('#prepare-export').addEventListener('click',()=>perform(async()=>{
  if(!active)return;const blob=await exportArchive(active);clearBackup();backupFile=new File([blob],safeFilename(active.name)+'.scan3d.json',{type:'application/json'});backupURL=URL.createObjectURL(blob);
  $('#download-backup').href=backupURL;$('#download-backup').download=backupFile.name;$('#download-backup').hidden=false;
  try{$('#share-backup').hidden=!(navigator.share&&navigator.canShare?.({files:[backupFile]}));}catch{$('#share-backup').hidden=true;}
  $('#backup-help').textContent='Projektfilen er klar. Vælg Hent projektfil eller Del projektfil… og derefter Gem i Filer. Bekræft selv, at filen findes.';status('Sikkerhedskopi klar · '+(blob.size/1024/1024).toFixed(1)+' MiB.');
}));
$('#share-backup').addEventListener('click',()=>{
  if(!backupFile)return;navigator.share({files:[backupFile],title:'Scan3D-projekt'}).then(()=>status('Browserens deling er afsluttet. Bekræft filen i Filer.')).catch(error=>status(error.name==='AbortError'?'Deling annulleret. Projektet er bevaret.':'Browseren kunne ikke dele filen. Brug Hent projektfil.',error.name!=='AbortError'));
});
$('#download-backup').addEventListener('click',()=>status('Browseren håndterer projektfilen. Bekræft selv, at den bliver gemt.'));
$('#choose-import').addEventListener('click',()=>$('#import-file').click());
$('#import-file').addEventListener('change',event=>{const file=event.target.files?.[0];event.target.value='';if(file)perform(async()=>{
  if(file.size>LIMITS.archive)throw new Error('Projektfilen overstiger 36 MiB.');await flush();
  const project=await importedPhotos(await importArchive(await file.text()));await commit(project);showTab(project.model?'model':'photo',true);
});});
$('#import-legacy').addEventListener('click',()=>perform(async()=>{
  await flush();const text=localStorage.getItem(LEGACY_KEY);const list=await importLegacyList(text),ready=[];
  for(const p of list)ready.push(await importedPhotos(p));const copies=await store.importLegacy(ready,'legacy-'+await sha256(new Blob([text])));
  active=copies[0];dirty=false;clearBackup();await refreshLibrary();render();status(copies.length+' tidligere projekt(er) importeret. Det oprindelige localStorage er bevaret.');
}));
document.addEventListener('visibilitychange',()=>{if(document.hidden){videoRecorder.stop();camera.stop();depth.stop();}});
window.addEventListener('pagehide',()=>{videoRecorder.stop();camera.stop();depth.stop();});
window.addEventListener('beforeunload',event=>{if(dirty||recording||recoveryURL){event.preventDefault();event.returnValue='';}});
async function boot() {
  try{
    await refreshLibrary();
    if(projects[0]){await verifyAssets(projects[0]);active=projects[0];}
    status(active?'Seneste projekt er åbnet. Kameraet er slukket.':'Opret et nyt projekt eller importér en sikkerhedskopi.');
  }catch(error){status(error.message,true);}
  try{$('#import-legacy').hidden=!localStorage.getItem(LEGACY_KEY);}catch{}
  busy=false;render();if(!videoRecorder.supported)$('#video-state').textContent='Denne browser kan ikke optage livevideo. Brug Vælg video. MP4 eller WebM skal kunne afspilles i browseren.';document.body.dataset.ready='true';
}
initLaunchHelp();
pwaUpdates = initPWAUpdates({
  button:$('#pwa-update'),
  isSafe:()=>canSwitchPWA({
    busy,dirty,recording,recovery:Boolean(recoveryURL),
    camera:cameraState,depth:depth.state
  })
});
boot();
