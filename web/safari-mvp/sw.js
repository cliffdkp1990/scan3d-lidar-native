/* Scan3D Safari review PWA: offline shell and network-first same-origin code.
 * This is NOT the deployed Vercel Atelier Studio worker; no upload or release.
 * Never cache camera/video/blob exports or delete user IndexedDB/localStorage.
 */
const PREFIX='scan3d-safari-shell-';
const CACHE=PREFIX+'20261028-1';
const SHELL=[
  './','./index.html','./app.css','./app.mjs',
  './launch.mjs','./launch-core.mjs',
  './core.mjs','./store.mjs','./camera.mjs','./geometry.mjs',
  './stl.mjs','./viewer.mjs','./record3d-session.mjs',
  './record3d-core.mjs','./record3d-session.mjs',
  './capture-guide.mjs','./capture-guide-core.mjs','./video.mjs',
  './manifest.webmanifest',
  './icons/scan3d-180.png','./icons/scan3d-192.png','./icons/scan3d-512.png'
];
const PATHS=new Set(SHELL.map(path=>new URL(path,self.registration.scope).pathname));
function allowed(request) {
  const url=new URL(request.url);
  return request.method==='GET' && url.origin===self.location.origin &&
    PATHS.has(url.pathname) && !url.username && !url.password;
}
function eligible(response) {
  return Boolean(response&&response.ok&&response.type==='basic');
}
async function networkFirst(request) {
  const cache=await caches.open(CACHE);
  try {
    const fresh=await fetch(request);
    if(!eligible(fresh))throw new Error('Static response is not cacheable');
    await cache.put(request,fresh.clone()).catch(()=>{});
    return fresh;
  }catch(error){
    const offline=await cache.match(request,{ignoreSearch:true});
    if(offline)return offline;
    if(request.mode==='navigate'){
      const fallback=await cache.match(new URL('./index.html',self.registration.scope));
      if(fallback)return fallback;
    }
    throw error;
  }
}
self.addEventListener('install',event=>{
  // First install becomes active normally. Updates stay waiting until the user
  // explicitly chooses an update outside an active capture/unsaved draft.
  event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(SHELL)));
});
self.addEventListener('activate',event=>{
  event.waitUntil((async()=>{
    const names=await caches.keys();
    await Promise.all(names.filter(name=>name.startsWith(PREFIX)&&name!==CACHE)
      .map(name=>caches.delete(name)));
    await self.clients.claim();
  })());
});
self.addEventListener('message',event=>{
  if(event.data?.type!=='SCAN3D_ACTIVATE_WHEN_SAFE')return;
  // Only the same-origin app UI can send this message to a waiting worker.
  // The UI's current-state check prevents interrupting video or unsaved work.
  if(!event.source||!event.source.url||
      new URL(event.source.url).origin!==self.location.origin)return;
  event.waitUntil(self.skipWaiting());
});
self.addEventListener('fetch',event=>{
  if(allowed(event.request))event.respondWith(networkFirst(event.request));
});
