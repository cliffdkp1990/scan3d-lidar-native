import {test,expect} from '@playwright/test';
test('actual Chrome WebRTC transports a synthetic depth frame without STUN or camera',async({page})=>{
  await page.goto('/');
  const result=await page.evaluate(async()=>{
    const source=document.createElement('canvas');source.width=64;source.height=32;const c=source.getContext('2d');
    const draw=()=>{c.fillStyle='#00ff00';c.fillRect(0,0,32,32);c.fillStyle='#e6d2aa';c.fillRect(32,0,32,32);};draw();
    const stream=source.captureStream(10),timer=setInterval(draw,100),a=new RTCPeerConnection({iceServers:[]}),b=new RTCPeerConnection({iceServers:[]});
    const video=document.createElement('video');video.muted=true;video.autoplay=true;video.playsInline=true;document.body.append(video);
    b.ontrack=e=>{video.srcObject=new MediaStream([e.track]);video.play().catch(()=>{});};
    const wait=condition=>new Promise((resolve,reject)=>{const deadline=Date.now()+8000;const poll=setInterval(()=>{if(condition()){clearInterval(poll);resolve();}else if(Date.now()>deadline){clearInterval(poll);reject(new Error('Synthetic WebRTC timed out'));}},50);});
    try{
      a.addTrack(stream.getVideoTracks()[0],stream);await a.setLocalDescription(await a.createOffer());await wait(()=>a.iceGatheringState==='complete');
      await b.setRemoteDescription(a.localDescription);await b.setLocalDescription(await b.createAnswer());await wait(()=>b.iceGatheringState==='complete');await a.setRemoteDescription(b.localDescription);
      await wait(()=>video.readyState>=2);const out=document.createElement('canvas');out.width=64;out.height=32;const x=out.getContext('2d');x.drawImage(video,0,0);const pixel=[...x.getImageData(16,16,1,1).data];
      const stats=[...(await b.getStats()).values()].filter(s=>s.type==='inbound-rtp'&&s.kind==='video');
      return{pixel,bytes:stats.reduce((n,s)=>n+(s.bytesReceived||0),0),width:video.videoWidth,height:video.videoHeight};
    }finally{clearInterval(timer);stream.getTracks().forEach(t=>t.stop());video.srcObject?.getTracks().forEach(t=>t.stop());video.remove();a.close();b.close();}
  });
  expect(result.width).toBe(64);expect(result.height).toBe(32);expect(result.pixel[1]).toBeGreaterThan(200);expect(result.pixel[0]).toBeLessThan(40);expect(result.bytes).toBeGreaterThan(0);
});
