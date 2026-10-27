import { defineConfig, devices } from '@playwright/test';
export default defineConfig({
  testDir:'./tests',testMatch:'browser.spec.mjs',fullyParallel:false,workers:1,retries:0,timeout:30000,
  outputDir:'test-results/artifacts',reporter:[['list'],['json',{outputFile:'test-results/results.json'}]],
  use:{baseURL:'http://127.0.0.1:4173',browserName:'webkit',trace:'retain-on-failure',screenshot:'only-on-failure'},
  webServer:{command:'node tools/serve.mjs --qa',url:'http://127.0.0.1:4173',reuseExistingServer:false,timeout:15000},
  projects:[
    {name:'webkit-iphone13-portrait',use:{...devices['iPhone 13'],viewport:{width:390,height:844}}},
    {name:'webkit-iphone13-landscape',use:{...devices['iPhone 13'],viewport:{width:844,height:390}}},
    {name:'webkit-desktop',use:{viewport:{width:1480,height:910},deviceScaleFactor:1}}
  ]
});
