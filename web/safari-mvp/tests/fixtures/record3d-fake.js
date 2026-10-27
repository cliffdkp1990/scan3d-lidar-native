// SYNTHETIC test transport. This does NOT prove phone connectivity or LiDAR.
// Pixel conversion, video decoding, storage and downloads remain real browser code.
(()=>{
  const state=window.__r3dTest={calls:[],closed:0,stopped:0,cameraRequests:0,badMetadata:false};
  const realFetch=window.fetch.bind(window);
  window.fetch=async(input,options={})=>{
    const url=String(input);if(!url.includes('/__scan3d/'))return realFetch(input,options);
    state.calls.push(url);
    if(url.endsWith('/status'))return new Response(JSON.stringify({record3dEnabled:true,token:'a'.repeat(64)}));
    const value=JSON.parse(options.body);
    if(value.operation==='metadata')return new Response(JSON.stringify({data:state.badMetadata?{}:{K:[300,0,160,0,300,120,0,0,1],originalSize:[320,240]}}));
    if(value.operation==='offer')return new Response(JSON.stringify({data:{type:'offer',sdp:'v=0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=candidate:1 1 udp 1 192.168.1.40 12345 typ host\r\n'}}));
    return new Response(JSON.stringify({data:{accepted:true}}));
  };
  Object.defineProperty(navigator,'mediaDevices',{configurable:true,value:{getUserMedia:async()=>{state.cameraRequests++;throw new Error('Real camera disabled in synthetic RGBD test');}}});
  window.RTCPeerConnection=class {
    constructor(config){state.config=config;this.iceGatheringState='complete';this.connectionState='new';}
    async setRemoteDescription(){
      const canvas=document.createElement('canvas');canvas.width=640;canvas.height=240;
      const context=canvas.getContext('2d');
      const draw=()=>{context.fillStyle='#00ff00';context.fillRect(0,0,320,240);context.fillStyle='#e6d2aa';context.fillRect(320,0,320,240);};draw();
      this.stream=canvas.captureStream(10);const track=this.stream.getVideoTracks()[0],stop=track.stop.bind(track);
      this.timer=setInterval(()=>{draw();track.requestFrame?.();},100);
      track.stop=()=>{state.stopped++;clearInterval(this.timer);stop();};
      queueMicrotask(()=>this.ontrack?.({track}));
    }
    async createAnswer(){return{type:'answer',sdp:'v=0\r\n'};}
    async setLocalDescription(answer){this.localDescription=answer;}
    close(){state.closed++;clearInterval(this.timer);this.connectionState='closed';}
  };
})();
