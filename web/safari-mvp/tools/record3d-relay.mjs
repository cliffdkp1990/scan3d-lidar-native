import http from 'node:http';
import {randomBytes,timingSafeEqual} from 'node:crypto';
import {privateIPv4,R3D} from '../record3d-core.mjs';
const fail=(message,status=400)=>Object.assign(new Error(message),{status});
async function jsonBody(req,signal) {
  return new Promise((resolve,reject)=>{
    let bytes=0,done=false;const parts=[];
    const finish=(error,value)=>{
      if(done)return;done=true;req.off('data',data);req.off('end',end);req.off('error',broken);signal.removeEventListener('abort',abort);
      if(error){req.resume();reject(error);}else resolve(value);
    };
    const data=part=>{bytes+=part.length;if(bytes>R3D.maxJSON)finish(fail('Forespørgslen er for stor.',413));else parts.push(part);};
    const end=()=>{try{finish(null,JSON.parse(Buffer.concat(parts).toString('utf8')));}catch{finish(fail('Ugyldig JSON.'));}};
    const broken=()=>finish(fail('Forespørgslen blev afbrudt.'));
    const abort=()=>finish(fail('Forespørgslen nåede tidsgrænsen.',408));
    req.on('data',data);req.once('end',end);req.once('error',broken);signal.addEventListener('abort',abort,{once:true});
    if(Number(req.headers['content-length'])>R3D.maxJSON)finish(fail('Forespørgslen er for stor.',413));
    else if(signal.aborted)abort();
  });
}
export function forwardRecord3D(address,operation,answer,signal) {
  privateIPv4(address);
  const paths={metadata:'/metadata',offer:'/getOffer',answer:'/answer'};
  if(!Object.hasOwn(paths,operation))throw fail('Ukendt Record3D-handling.');
  if(operation==='answer'&&(!answer||answer.type!=='answer'||typeof answer.data!=='string'||answer.data.length>R3D.maxJSON||!answer.data.startsWith('v=0')))throw fail('Ugyldigt WebRTC-svar.');
  const body=operation==='answer'?Buffer.from(JSON.stringify(answer)):null;
  return new Promise((resolve,reject)=>{
    const request=http.request({hostname:address,port:80,path:paths[operation],method:body?'POST':'GET',signal,timeout:5000,
      headers:body?{'Content-Type':'application/json','Content-Length':body.length}:{}},response=>{
      if(response.statusCode<200||response.statusCode>=300){response.resume();reject(fail('Record3D svarede ikke med succes. Stop/start streamen i telefonappen.',502));return;}
      let size=0;const chunks=[];
      response.on('data',chunk=>{size+=chunk.length;if(size>R3D.maxJSON){response.destroy();reject(fail('Telefonens svar er for stort.',502));}else chunks.push(chunk);});
      response.on('error',()=>reject(fail('Telefonens svar blev afbrudt.',502)));
      response.on('end',()=>{
        if(operation==='answer'){resolve({accepted:true});return;}
        try{resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));}catch{reject(fail('Telefonen leverede ikke JSON.',502));}
      });
    });
    request.on('timeout',()=>request.destroy(new Error('timeout')));
    request.on('error',()=>reject(fail('Telefonen kunne ikke nås. Kontroller privat Wi-Fi, IPv4 og Record3D-streaming.',502)));
    request.end(body);
  });
}
export function createRecord3DRelay({enabled=false,origin,forward=forwardRecord3D,timeoutMs=6500}={}) {
  const token=randomBytes(32).toString('hex');
  const headers={'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Cross-Origin-Resource-Policy':'same-origin'};
  const send=(res,status,data)=>res.writeHead(status,headers).end(JSON.stringify(data));
  return async(req,res)=>{
    const path=req.url?.split('?')[0];
    if(!['/__scan3d/status','/__scan3d/record3d'].includes(path))return false;
    if(req.headers.host!==new URL(origin).host){send(res,403,{error:'Forkert host.'});return true;}
    if(path==='/__scan3d/status'&&req.method==='GET'){
      send(res,200,{app:'scan3d-local',record3dEnabled:enabled,...(enabled?{token}:{})});return true;
    }
    if(!enabled){send(res,403,{error:'Start den lokale server med --record3d for at aktivere forbindelsen.'});return true;}
    const supplied=req.headers['x-scan3d-token'];
    if(req.method!=='POST'||req.headers.origin!==origin||req.headers['content-type']!=='application/json'||typeof supplied!=='string'||!/^[a-f0-9]{64}$/.test(supplied)||!timingSafeEqual(Buffer.from(supplied),Buffer.from(token))){send(res,403,{error:'Forbindelsen kræver samme origin og en gyldig lokal session.'});return true;}
    const controller=new AbortController();
    const timer=setTimeout(()=>controller.abort(),timeoutMs);
    req.once('aborted',()=>controller.abort());res.once('close',()=>{if(!res.writableEnded)controller.abort();});
    try{
      const value=await jsonBody(req,controller.signal);privateIPv4(value?.address);
      if(!['metadata','offer','answer'].includes(value.operation))throw fail('Ukendt handling.');
      if(value.operation==='answer'&&(!value.answer||value.answer.type!=='answer'||typeof value.answer.data!=='string'||value.answer.data.length>R3D.maxJSON||!value.answer.data.startsWith('v=0')))throw fail('Ugyldigt WebRTC-svar.');
      const data=await forward(value.address,value.operation,value.answer,controller.signal);
      send(res,200,{data});
    }catch(error){if(!res.destroyed)send(res,error.status||400,{error:error.message||'Lokal forbindelsesfejl.'});req.resume();}
    finally{clearTimeout(timer);}
    return true;
  };
}
