import {test,expect} from '@playwright/test';
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {parseGeometry} from '../geometry.mjs';
const errors=new WeakMap();
test.beforeEach(async({page})=>{const list=[];errors.set(page,list);page.on('pageerror',e=>list.push(e.message));});
test.afterEach(async({page})=>expect(errors.get(page)).toEqual([]));
test.afterAll(async({browser},info)=>writeFile(info.outputPath('engine.json'),JSON.stringify({project:info.project.name,browser:browser.version(),channel:info.project.use.channel||'webkit',physicalIPhone:false,physicalLiDAR:false},null,2)));
async function ready(page){await page.goto('/?qa=record3d-fake');await expect(page.locator('body')).toHaveAttribute('data-ready','true');await page.locator('#depth-options').evaluate(e=>e.open=true);}
async function original(page){await page.locator('#new-project').click();await expect(page.locator('#save-state')).toHaveAttribute('data-saved','true');await page.locator('#project-name').fill('Bevar original');await page.locator('#save-project').click();await expect(page.locator('#save-state')).toHaveAttribute('data-saved','true');}
async function connect(page){await page.locator('#depth-address').fill('192.168.1.40');await page.locator('#depth-encoding').check();await page.locator('#connect-depth').click();await expect(page.locator('#rgbd-state')).toHaveAttribute('data-state','live');}
async function download(page,selector){const event=page.waitForEvent('download');await page.locator(selector).click();const d=await event;expect(await d.failure()).toBeNull();return readFile(await d.path());}
test('synthetic RGBD snapshot creates a separate project, exports and reopens identical PLY',async({page},info)=>{
  await ready(page);await original(page);await connect(page);
  expect(await page.evaluate(()=>window.__r3dTest.config.iceServers)).toEqual([]);
  await expect(page.locator('#rgbd-state')).toContainText('sensor ikke bekræftet');
  await page.locator('#capture-depth').click();await expect(page.locator('#project-count')).toHaveText('2');await expect(page.locator('#export-model')).toBeVisible();
  const bytes=await download(page,'#export-model'),geometry=parseGeometry(bytes.toString(),'snapshot.ply');
  expect(geometry.faces).toHaveLength(0);expect(geometry.vertices.length).toBeGreaterThan(1000);expect(geometry.vertices.length).toBeLessThanOrEqual(20000);
  expect(geometry.vertices.every(v=>Math.abs(v[2]+1)<.03)).toBe(true);expect(bytes.toString()).toContain('sensor unverified');
  await page.locator('#prepare-export').click();const backup=await download(page,'#download-backup'),raw=JSON.parse(backup);
  expect(createHash('sha256').update(bytes).digest('hex')).toBe(raw.project.model.sha256);
  await page.locator('#depth-panel').screenshot({path:info.outputPath('synthetic-rgbd-receiver.png')});
  await page.reload();await expect(page.locator('body')).toHaveAttribute('data-ready','true');await page.locator('#model-tab').click();
  expect(await download(page,'#export-model')).toEqual(bytes);
  expect(await page.evaluate(()=>window.__r3dTest.calls.length)).toBe(0);
  await page.locator('#import-file').setInputFiles({name:'snapshot.scan3d.json',mimeType:'application/json',buffer:backup});await expect(page.locator('#project-count')).toHaveText('3');
  await page.locator('#open-library').click();await page.getByRole('button',{name:/Bevar original/}).click();await expect(page.locator('#project-name')).toHaveValue('Bevar original');await expect(page.locator('#photo-count')).toHaveText('0');
  expect(await page.evaluate(()=>window.__r3dTest.cameraRequests)).toBe(0);
});
test('invalid phone address cannot start network or replace a saved project',async({page})=>{
  await ready(page);await original(page);await page.locator('#depth-address').fill('8.8.8.8');await page.locator('#connect-depth').click();
  await expect(page.locator('#status')).toHaveAttribute('data-error','true');await expect(page.locator('#project-count')).toHaveText('1');await expect(page.locator('#capture-depth')).toBeDisabled();
  expect(await page.evaluate(()=>window.__r3dTest.calls.length)).toBe(0);
});
test('missing camera metadata fails closed and releases the received video',async({page})=>{
  await ready(page);await original(page);await page.evaluate(()=>window.__r3dTest.badMetadata=true);
  await page.locator('#depth-address').fill('192.168.1.40');await page.locator('#depth-encoding').check();await page.locator('#connect-depth').click();
  await expect(page.locator('#status')).toContainText('K og originalSize');await expect(page.locator('#rgbd-state')).toHaveAttribute('data-state','stopped');
  await expect(page.locator('#capture-depth')).toBeDisabled();await expect(page.locator('#project-count')).toHaveText('1');
  expect(await page.locator('#rgbd-video').evaluate(v=>v.srcObject)).toBeNull();expect(await page.evaluate(()=>window.__r3dTest.stopped)).toBeGreaterThan(0);
});
test('manual stop and pagehide release tracks; no automatic reconnect or project mutation',async({page})=>{
  await ready(page);await original(page);await connect(page);await page.locator('#stop-depth').click();await expect(page.locator('#rgbd-state')).toHaveAttribute('data-state','stopped');
  await connect(page);await page.evaluate(()=>window.dispatchEvent(new PageTransitionEvent('pagehide')));
  await expect(page.locator('#rgbd-state')).toHaveAttribute('data-state','stopped');expect(await page.locator('#rgbd-video').evaluate(v=>v.srcObject)).toBeNull();
  expect(await page.evaluate(()=>window.__r3dTest.closed)).toBe(2);await expect(page.locator('#project-count')).toHaveText('1');
});
test('receiver remains readable at 22px and has no horizontal overflow',async({page},info)=>{
  await ready(page);await page.evaluate(()=>document.documentElement.style.fontSize='22px');
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  for(const control of await page.locator('#depth-panel button, #depth-address').all()){const box=await control.boundingBox();expect(box.height).toBeGreaterThanOrEqual(44);expect(box.x).toBeGreaterThanOrEqual(0);expect(box.x+box.width).toBeLessThanOrEqual(page.viewportSize().width);}
  await page.screenshot({path:info.outputPath('chrome-depth-layout-22px.png'),fullPage:true});
});
test('failed save of an existing dirty draft prevents a depth snapshot from replacing it',async({page,context})=>{
  await ready(page);await original(page);await page.locator('#project-name').fill('Bevar min kladde');
  await page.evaluate(()=>{const put=IDBObjectStore.prototype.put;IDBObjectStore.prototype.put=function(value,...args){const request=put.call(this,value,...args);if(this.name==='projects')this.transaction.abort();return request;};});
  await connect(page);await page.locator('#capture-depth').click();await expect(page.locator('#status')).toHaveAttribute('data-error','true');
  await expect(page.locator('#project-name')).toHaveValue('Bevar min kladde');await expect(page.locator('#save-state')).toHaveAttribute('data-saved','false');await expect(page.locator('#project-count')).toHaveText('1');
  const other=await context.newPage();await ready(other);await expect(other.locator('#project-name')).toHaveValue('Bevar original');await expect(other.locator('#project-count')).toHaveText('1');await other.close();
});
test('failed snapshot storage stays an exportable draft and never reports a successful save',async({page})=>{
  await ready(page);await original(page);
  await page.evaluate(()=>{const put=IDBObjectStore.prototype.put;IDBObjectStore.prototype.put=function(value,...args){const request=put.call(this,value,...args);if(this.name==='projects'&&value.model)this.transaction.abort();return request;};});
  await connect(page);await page.locator('#capture-depth').click();await expect(page.locator('#save-state')).toHaveAttribute('data-saved','false');await expect(page.locator('#status')).toHaveAttribute('data-error','true');await expect(page.locator('#project-count')).toHaveText('1');
  await expect(page.locator('#export-model')).toBeVisible();expect(parseGeometry((await download(page,'#export-model')).toString(),'draft.ply').vertices.length).toBeGreaterThan(1000);
  await page.locator('#prepare-export').click();const backup=JSON.parse(await download(page,'#download-backup'));expect(backup.project.model.name).toBe('Record3D-RGBD.ply');
});
