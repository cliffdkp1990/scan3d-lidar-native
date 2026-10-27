import test from 'node:test';
import assert from 'node:assert/strict';
import {privateIPv4,videoOffer,calibration,pixelDepth,framePLY,R3D} from '../record3d-core.mjs';
import {parseGeometry} from '../geometry.mjs';
import {newProject,makeAsset,exportArchive,importArchive,verifyAssets} from '../core.mjs';
const ip='192.168.1.40';
const meta={K:[8,0,4,0,8,4,0,0,1],originalSize:[8,8]};
const offer=(extra='')=>({type:'offer',sdp:'v=0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=candidate:1 1 udp 1 '+ip+' 12345 typ host\r\n'+extra});
function frame(w=16,h=8){const data=new Uint8ClampedArray(w*h*4);for(let y=0;y<h;y++)for(let x=0;x<w;x++){const i=(y*w+x)*4;data.set(x<w/2?[0,255,0,255]:[230,210,170,255],i);}return data;}
test('private IPv4 accepts only canonical RFC1918 unicast candidates',()=>{
  for(const v of [ip,'10.1.2.3','172.16.0.1','172.31.1.2'])assert.equal(privateIPv4(v),v);
  for(const v of ['127.0.0.1','169.254.1.1','8.8.8.8','172.32.1.1','192.168.1.255','10.0.0.0','010.1.2.3','192.168.1.40:80','http://192.168.1.40','localhost','::1',null])assert.throws(()=>privateIPv4(v));
});
test('SDP retains selected private host only and refuses audio/data or missing host',()=>{
  const result=videoOffer(offer('a=candidate:2 1 udp 1 8.8.8.8 123 typ srflx\r\na=remote-candidates:1 8.8.8.8 123\r\n'),ip);
  assert.ok(result.sdp.includes(ip));assert.ok(!result.sdp.includes('8.8.8.8'));
  for(const extra of ['m=audio 9 UDP/TLS/RTP/SAVPF 96\r\n','m=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\n','m=video 9 UDP/TLS/RTP/SAVPF 96\r\n'])assert.throws(()=>videoOffer(offer(extra),ip));
  assert.throws(()=>videoOffer({...offer(),sdp:offer().sdp.replace(ip,'8.8.8.8')},ip));
  assert.throws(()=>videoOffer({type:'answer',sdp:'v=0'},ip));
});
test('calibration accepts documented row/column layouts without guessing dimensions',()=>{
  const expected=calibration(meta,16,8);assert.equal(expected.fx,8);
  assert.deepEqual(calibration({...meta,K:[8,0,0,0,8,0,4,4,1]},16,8),expected);
  for(const m of [{K:meta.K},{...meta,originalSize:[8,4]},{...meta,K:[0,0,4,0,8,4,0,0,1]},{...meta,K:[8,0,4,0,8,4,4,4,1]}])assert.throws(()=>calibration(m,16,8));
  for(const size of [[15,8],[16,0],[8000,8000]])assert.throws(()=>calibration(meta,...size));
});
test('HSV depth rejects invalid red, white, dark and desaturated samples',()=>{
  assert.ok(Math.abs(pixelDepth(0,255,0)-1)<1e-12);assert.ok(Math.abs(pixelDepth(0,0,255)-2)<1e-12);
  for(const c of [[255,0,0],[255,255,255],[0,0,0],[1,1,2]])assert.ok(Number.isNaN(pixelDepth(...c)));
});
test('calibrated synthetic depth makes finite camera-relative XYZ, not an artificial mesh',()=>{
  const geometry=parseGeometry(framePLY(frame(),16,8,meta),'frame.ply');
  assert.equal(geometry.vertices.length,36);assert.equal(geometry.faces.length,0);assert.equal(geometry.isPointCloud,true);
  assert.deepEqual(geometry.vertices[0],[-.375,.375,-1]);
  assert.throws(()=>framePLY(new Uint8ClampedArray(2),16,8,meta));
  assert.throws(()=>framePLY(new Uint8ClampedArray(16*8*4),16,8,meta));
});
test('neighbourhood filter removes depth discontinuities; frame bound is enforced',()=>{
  const data=frame();data.set([0,0,255,255],(3*16+3)*4);
  assert.equal(parseGeometry(framePLY(data,16,8,meta),'f.ply').vertices.length,27);
  const g=parseGeometry(framePLY(frame(1920,960),1920,960,{K:[960,0,480,0,960,480,0,0,1],originalSize:[960,960]}),'f.ply');
  assert.ok(g.vertices.length<=R3D.maxPoints);assert.ok(g.vertices.length>1000);
});
test('depth snapshot survives project export/import byte-exact with integrity and warning',async()=>{
  const text=framePLY(frame(),16,8,meta),p=newProject('RGBD');
  p.model=await makeAsset(new Blob([text],{type:'text/plain'}),'Record3D-RGBD.ply',{origin:'import'});
  const copy=await importArchive(await (await exportArchive(p)).text());await verifyAssets(copy);
  assert.notEqual(copy.id,p.id);assert.equal(await copy.model.blob.text(),text);assert.match(text,/sensor unverified.*no fusion/);
});
