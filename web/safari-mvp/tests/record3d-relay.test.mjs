import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {createRecord3DRelay,forwardRecord3D} from '../tools/record3d-relay.mjs';
async function server(t,enabled=true,options={}){
  const calls=[];let handler;
  const s=http.createServer((req,res)=>handler(req,res).then(used=>{if(!used)res.writeHead(404).end();}));
  await new Promise(resolve=>s.listen(0,'127.0.0.1',resolve));
  const origin='http://127.0.0.1:'+s.address().port;
  handler=createRecord3DRelay({enabled,origin,forward:async(...args)=>{calls.push(args.slice(0,3));return {ok:true};},...options});
  t.after(()=>{s.closeAllConnections();s.close();});
  const status=await (await fetch(origin+'/__scan3d/status')).json();
  const post=(value,headers={})=>fetch(origin+'/__scan3d/record3d',{method:'POST',headers:{Origin:origin,'Content-Type':'application/json','X-Scan3D-Token':status.token,...headers},body:JSON.stringify(value)});
  return{origin,calls,status,post};
}
const value={address:'192.168.1.40',operation:'metadata'};
test('relay is disabled by default and does not disclose a token',async t=>{
  const s=await server(t,false);assert.equal(s.status.record3dEnabled,false);assert.equal(s.status.token,undefined);assert.equal((await s.post(value)).status,403);assert.deepEqual(s.calls,[]);
});
test('relay forwards explicit private fixed operations only after same-origin session check',async t=>{
  const s=await server(t);assert.match(s.status.token,/^[a-f0-9]{64}$/);
  assert.equal((await s.post(value)).status,200);assert.deepEqual(s.calls[0],['192.168.1.40','metadata',undefined]);
  const answer={type:'answer',data:'v=0\r\n'};
  assert.equal((await s.post({...value,operation:'answer',answer})).status,200);assert.deepEqual(s.calls[1][2],answer);
});
test('wrong Host, cross-origin requests and malformed/Unicode tokens never forward',async t=>{
  const s=await server(t);
  for(const h of [{Origin:'https://example.com'},{'X-Scan3D-Token':'é'.repeat(64)},{'X-Scan3D-Token':'0'.repeat(64)},{'Content-Type':'text/plain'}])assert.equal((await s.post(value,h)).status,403);
  const wrongHost=await new Promise((resolve,reject)=>{const req=http.request(s.origin+'/__scan3d/record3d',{method:'POST',headers:{Host:'evil.example',Origin:s.origin,'Content-Type':'application/json','X-Scan3D-Token':s.status.token}},res=>{res.resume();resolve(res.statusCode);});req.on('error',reject);req.end(JSON.stringify(value));});
  assert.equal(wrongHost,403);
  assert.deepEqual(s.calls,[]);
});
test('relay rejects public hosts, arbitrary paths, invalid answer and oversized body',async t=>{
  const s=await server(t);
  for(const v of [{...value,address:'8.8.8.8'},{...value,address:'http://192.168.1.40'},{...value,operation:'/admin'},{...value,operation:'answer',answer:{type:'offer',data:'v=0'}}])assert.equal((await s.post(v)).status,400);
  assert.equal((await s.post({...value,padding:'a'.repeat(262144)})).status,413);assert.deepEqual(s.calls,[]);
  assert.throws(()=>forwardRecord3D('127.0.0.1','metadata'));assert.throws(()=>forwardRecord3D(value.address,'/admin'));assert.throws(()=>forwardRecord3D(value.address,'answer',{}));
});
test('slow incoming JSON reaches a bounded timeout before any upstream call',async t=>{
  const s=await server(t,true,{timeoutMs:100});
  const status=await new Promise((resolve,reject)=>{
    const request=http.request(s.origin+'/__scan3d/record3d',{method:'POST',headers:{Origin:s.origin,'Content-Type':'application/json','X-Scan3D-Token':s.status.token,'Transfer-Encoding':'chunked'}},response=>{response.resume();resolve(response.statusCode);request.destroy();});
    request.on('error',reject);request.write('{');
  });
  assert.equal(status,408);assert.deepEqual(s.calls,[]);
});
