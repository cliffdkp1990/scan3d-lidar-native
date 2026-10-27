import {defineConfig} from '@playwright/test';
const sizes=[['portrait',390,844],['landscape',844,390],['desktop',1480,910]];
export default defineConfig({
  testDir:'./tests',testMatch:['browser.spec.mjs','record3d.browser.spec.mjs','record3d.rtc.spec.mjs'],fullyParallel:false,workers:1,retries:0,timeout:30000,
  outputDir:'test-results/chrome-artifacts',reporter:[['list'],['json',{outputFile:'test-results/chrome-results.json'}]],
  use:{baseURL:'http://127.0.0.1:4173',trace:'retain-on-failure',screenshot:'only-on-failure'},
  webServer:{command:'node tools/serve.mjs --qa',url:'http://127.0.0.1:4173',reuseExistingServer:false,timeout:30000},
  projects:[
    ...sizes.map(([name,width,height])=>({name:'chrome-'+name,use:{browserName:'chromium',channel:'chrome',viewport:{width,height},deviceScaleFactor:1,isMobile:name!=='desktop',hasTouch:name!=='desktop'}})),
    ...sizes.map(([name,width,height])=>({name:'webkit-rgbd-'+name,testMatch:'record3d.browser.spec.mjs',use:{browserName:'webkit',viewport:{width,height},deviceScaleFactor:1,isMobile:name!=='desktop',hasTouch:name!=='desktop'}}))
  ]
});
