import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {webkit,devices} from '../../web/safari-mvp/node_modules/playwright/index.mjs';
const dir=process.env.BRIDGE_FIXTURE_DIR, output=process.env.BRIDGE_REPORT_DIR;
assert.ok(dir&&output,'Requires actual Swift-generated fixtures and a report directory');
await mkdir(output,{recursive:true});
const browser=await webkit.launch();
const results=[];
try {
  for(const [name,size] of [['portrait',[390,844]],['landscape',[844,390]],['desktop',[1480,910]]]) {
    const context=await browser.newContext({...(name==='desktop'?{deviceScaleFactor:1}:devices['iPhone 13']),viewport:{width:size[0],height:size[1]}});
    const page=await context.newPage(),errors=[];
    page.on('pageerror',error=>errors.push(error.message));
    const response=await page.goto('http://127.0.0.1:4173');assert.equal(response.status(),200);
    await page.locator('body[data-ready="true"]').waitFor();
    for(const [index,ext] of ['ply','obj'].entries()) {
      await page.locator('#choose-import').waitFor({state:'visible'});
      await page.locator('#import-file').setInputFiles(resolve(dir,'native-'+ext+'.scan3d.json'));
      await page.locator('#model-canvas[data-state="ready"]').waitFor();
      await page.waitForFunction(n=>document.querySelector('#project-count').textContent===String(n)&&!document.querySelector('#new-project').disabled,index+1);
      await page.waitForFunction(n=>document.querySelector('#model-canvas').dataset.triangles===String(n),ext==='obj'?1:0);
      assert.equal(await page.locator('#model-canvas').getAttribute('data-vertices'),'3');
      assert.equal(await page.locator('#model-canvas').getAttribute('data-triangles'),ext==='obj'?'1':'0');
      const pending=page.waitForEvent('download');await page.locator('#export-model').click();
      const downloaded=await pending;
      assert.deepEqual(await readFile(await downloaded.path()),await readFile(resolve(dir,'original.'+ext)));
      await page.reload();await page.locator('body[data-ready="true"]').waitFor();
      await page.locator('#model-tab').click();await page.locator('#model-canvas[data-state="ready"]').waitFor();
      assert.equal(await page.locator('#save-state').getAttribute('data-saved'),'true');
      await page.locator('#model-panel').screenshot({path:resolve(output,name+'-'+ext+'-SYNTHETIC.png')});
    }
    const broken=JSON.parse(await readFile(resolve(dir,'native-obj.scan3d.json'),'utf8'));broken.project.model.sha256='0'.repeat(64);
    await page.locator('#import-file').setInputFiles({name:'bad.scan3d.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(broken))});
    await page.locator('#status[data-error="true"]').waitFor();
    assert.equal(await page.locator('#project-count').textContent(),'2');
    assert.equal(await page.locator('#save-state').getAttribute('data-saved'),'true');
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),true);
    assert.deepEqual(errors,[]);
    results.push({viewport:size,name,ply:true,obj:true,reload:true,byteExactDownloads:true,corruptImportPreservesProjects:true,noPageErrors:true});
    await context.close();
  }
} finally {await browser.close();await writeFile(resolve(output,'browser.json'),JSON.stringify({checkout:process.env.SOURCE_COMMIT,results,physicalIPhone:false,physicalLiDAR:false,syntheticFixtures:true},null,2));}
assert.equal(results.length,3);
console.log('3 WebKit viewport suites passed: actual Swift PLY/OBJ archives, IndexedDB reload, 6 byte-exact model downloads and 3 rejected corrupt imports.');
