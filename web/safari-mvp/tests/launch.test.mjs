import test from 'node:test';import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {launchContext,cameraChecks} from '../launch-core.mjs';
test('iPhone Chrome, iPad desktop mode and standalone are detected without conflating browsers',()=>{
 assert.deepEqual(launchContext({userAgent:'iPhone CriOS/154',standalone:true}),{ios:true,chromeIOS:true,standalone:true});
 assert.equal(launchContext({userAgent:'Macintosh',platform:'MacIntel',maxTouchPoints:5}).ios,true);
 assert.equal(launchContext({userAgent:'Windows Chrome/154'}).ios,false);
 assert.deepEqual(launchContext({userAgent:'iPhone Version/27 Safari/604.1',standalone:false}),{ios:true,chromeIOS:false,standalone:false});
});
test('unknown permission or policy does not claim camera permission was granted',()=>{
 const rows=cameraChecks({secure:true,mediaAvailable:true,policyAllowed:undefined});
 assert.match(rows[2].value,/kan ikke aflæses/);assert.match(rows[3].value,/Kan ikke aflæses/);
 const denied=cameraChecks({secure:false,mediaAvailable:false,policyAllowed:false,permission:'denied',framed:true});
 assert.ok(denied.every(row=>!row.ok));
});
test('manifest stays relative to the app route, requests standalone and contains no external resources',async()=>{
 const manifest=JSON.parse(await readFile(new URL('../manifest.webmanifest',import.meta.url),'utf8'));
 assert.equal(manifest.display,'standalone');assert.equal(manifest.start_url,'./');assert.equal(manifest.scope,'./');assert.equal(manifest.id,'./');
 for(const icon of manifest.icons){assert.match(icon.src,/^\.\/icons\/scan3d-(192|512)\.png$/);const bytes=await readFile(new URL('../'+icon.src,import.meta.url));assert.deepEqual([...bytes.subarray(0,8)],[137,80,78,71,13,10,26,10]);const size=Number(icon.sizes.split('x')[0]);assert.equal(bytes.readUInt32BE(16),size);assert.equal(bytes.readUInt32BE(20),size);}
});
