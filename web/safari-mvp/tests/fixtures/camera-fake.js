// Synthetic canvas stream; never opens a real camera or microphone.
const fixtureCanvas=document.createElement('canvas');fixtureCanvas.width=640;fixtureCanvas.height=480;
const fixtureContext=fixtureCanvas.getContext('2d');
fixtureContext.fillStyle='#184b3c';fixtureContext.fillRect(0,0,640,480);fixtureContext.fillStyle='#eadcb6';fixtureContext.fillRect(230,100,180,280);
fixtureContext.fillStyle='white';fixtureContext.font='22px sans-serif';fixtureContext.fillText('SYNTHETIC CAMERA TEST',24,44);
Object.defineProperty(navigator,'mediaDevices',{configurable:true,value:{getUserMedia:async()=>{
  const stream=fixtureCanvas.captureStream(1);const track=stream.getVideoTracks()[0];track.requestFrame?.();return stream;
}}});
