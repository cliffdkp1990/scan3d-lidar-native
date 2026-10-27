import {privateIPv4,videoOffer,calibration,framePLY} from './record3d-core.mjs';

// No camera permission, STUN/TURN service, microphone, or automatic reconnect.
export class Record3DSession {
  constructor(video,onState=()=>{}) { this.video=video;this.onState=onState;this.state='stopped';this.current=null; }
  update(state,message) { this.state=state;this.onState(state,message); }
  stop(message='Forbindelsen er stoppet.') {
    const old=this.current;this.current=null;
    old?.controller.abort();old?.pc?.close();
    this.video.pause();this.video.srcObject?.getTracks().forEach(track=>track.stop());this.video.srcObject=null;this.video.load();
    this.update('stopped',message);
  }
  async start(address,{encodingConfirmed=false}={}) {
    privateIPv4(address);
    if(!encodingConfirmed)throw new Error('Bekræft Record3D Wi-Fi max. depth = 3 m, før du forbinder. En anden værdi giver forkert dybde.');
    this.stop();
    if(!globalThis.RTCPeerConnection)throw new Error('Browseren understøtter ikke WebRTC. Brug den aktuelle Chrome-version.');
    const run={controller:new AbortController(),pc:null,metadata:null};this.current=run;
    const signal=run.controller.signal;
    const timer=setTimeout(()=>run.controller.abort(),20000);
    this.update('connecting','Forbinder til Record3D på dit lokale Wi-Fi…');
    const request=async(url,options={})=>{
      const response=await fetch(url,{...options,signal,cache:'no-store',credentials:'omit',redirect:'error'});
      const text=await response.text();if(text.length>262144)throw new Error('Forbindelsens svar er for stort.');
      let data;try{data=JSON.parse(text);}catch{throw new Error('Start den lokale Chrome-server med --record3d.');}
      if(!response.ok)throw new Error(data.error||'Forbindelsen blev afvist.');return data;
    };
    const waitFor=condition=>new Promise((resolve,reject)=>{
      let poll;
      const finish=error=>{clearInterval(poll);signal.removeEventListener('abort',abort);error?reject(error):resolve();};
      const abort=()=>finish(new Error('Forbindelsen blev afbrudt eller nåede tidsgrænsen.'));
      signal.addEventListener('abort',abort,{once:true});
      poll=setInterval(()=>{if(condition())finish();},50);
      if(signal.aborted)abort();else if(condition())finish();
    });
    try {
      const local=await request('./__scan3d/status');
      if(!local.record3dEnabled||typeof local.token!=='string')throw new Error('Åbn Chrome på Windows med Start-Chrome-LiDAR.ps1. Record3D skal køre på din iPhone.');
      const relay=async(operation,answer)=> (await request('./__scan3d/record3d',{method:'POST',headers:{'Content-Type':'application/json','X-Scan3D-Token':local.token},body:JSON.stringify({address,operation,...(answer?{answer}:{})})})).data;
      run.metadata=await relay('metadata');
      const offer=videoOffer(await relay('offer'),address);
      const pc=new RTCPeerConnection({iceServers:[],bundlePolicy:'max-bundle'});run.pc=pc;
      pc.onconnectionstatechange=()=>{if(this.current===run&&['failed','disconnected','closed'].includes(pc.connectionState))this.stop('Streamen blev afbrudt. Start den igen i Record3D og forbind på ny.');};
      pc.ontrack=event=>{
        if(this.current!==run)return;
        if(event.track.kind!=='video'){event.track.stop();this.stop('Kun video må modtages.');return;}
        this.video.srcObject=new MediaStream([event.track]);
        this.video.play().catch(()=>{if(this.current===run)this.stop('Videoen kunne ikke afspilles. Prøv at forbinde igen.');});
      };
      await pc.setRemoteDescription(offer);await pc.setLocalDescription(await pc.createAnswer());
      await waitFor(()=>pc.iceGatheringState==='complete');
      await relay('answer',{type:'answer',data:pc.localDescription.sdp});
      await waitFor(()=>this.video.readyState>=2&&this.video.videoWidth>0);
      calibration(run.metadata,this.video.videoWidth,this.video.videoHeight);
      if(this.current!==run||signal.aborted)throw new Error('Forbindelsen blev stoppet.');
      clearTimeout(timer);this.update('live','Live RGBD · Record3D · sensor ikke bekræftet. Gem et dybdeudsnit, når motivet står roligt.');
    } catch(error) {
      if(this.current===run)this.stop(error.name==='AbortError'?'Forbindelsen nåede tidsgrænsen. Kontroller telefon og Wi-Fi.':error.message);
      throw error;
    } finally { clearTimeout(timer); }
  }
  snapshot() {
    const run=this.current,video=this.video;
    if(this.state!=='live'||!run||video.readyState<2)throw new Error('Forbind en RGBD-stream først.');
    calibration(run.metadata,video.videoWidth,video.videoHeight);
    const canvas=document.createElement('canvas');canvas.width=video.videoWidth;canvas.height=video.videoHeight;
    const context=canvas.getContext('2d',{willReadFrequently:true});
    if(!context)throw new Error('Browseren kunne ikke læse dybdebilledet.');
    context.drawImage(video,0,0);
    return framePLY(context.getImageData(0,0,canvas.width,canvas.height).data,canvas.width,canvas.height,run.metadata);
  }
}
