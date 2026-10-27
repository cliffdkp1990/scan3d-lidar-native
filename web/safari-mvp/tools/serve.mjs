import http from 'node:http';
import { readFile, realpath } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve, sep, extname } from 'node:path';
const root=await realpath(fileURLToPath(new URL('../',import.meta.url)));
const port=Number(process.env.PORT||4173),qa=process.argv.includes('--qa');
const fixtures=new Set(['camera-fake','camera-denied','storage-denied','no-webgl']);
const types={'.html':'text/html; charset=utf-8','.mjs':'application/javascript; charset=utf-8','.js':'application/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.json':'application/json','.png':'image/png','.obj':'text/plain','.ply':'text/plain'};
const server=http.createServer(async(req,res)=>{
  const headers={'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer','Permissions-Policy':'camera=(self), microphone=()','Cross-Origin-Resource-Policy':'same-origin'};
  if(!['GET','HEAD'].includes(req.method)){res.writeHead(405,headers).end();return;}
  try{
    const url=new URL(req.url,'http://127.0.0.1'),path=decodeURIComponent(url.pathname),target=await realpath(resolve(root,'.'+(path==='/'?'/index.html':path)));
    if(!target.startsWith(root+sep)||!types[extname(target)]){res.writeHead(404,headers).end();return;}
    let body=await readFile(target);
    if(qa&&target===resolve(root,'index.html')&&fixtures.has(url.searchParams.get('qa'))){
      body=Buffer.from(body.toString('utf8').replace('<head>','<head><script src="./tests/fixtures/'+url.searchParams.get('qa')+'.js"></script>'));
    }
    res.writeHead(200,{...headers,'Content-Type':types[extname(target)],'Content-Length':body.length});res.end(req.method==='HEAD'?undefined:body);
  }catch{res.writeHead(404,headers).end();}
});
server.listen(port,'127.0.0.1',()=>console.log('Scan3D Safari review: http://127.0.0.1:'+port+'/'));
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>server.close(()=>process.exit(0)));
