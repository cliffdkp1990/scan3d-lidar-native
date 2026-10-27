// Synthetic canvas stream; never opens a real camera or microphone.
const fixtureCanvas=document.createElement('canvas');fixtureCanvas.width=640;fixtureCanvas.height=480;
const fixtureContext=fixtureCanvas.getContext('2d');
fixtureContext.fillStyle='#184b3c';fixtureContext.fillRect(0,0,640,480);fixtureContext.fillStyle='#eadcb6';fixtureContext.fillRect(230,100,180,280);
fixtureContext.fillStyle='white';fixtureContext.font='22px sans-serif';fixtureContext.fillText('SYNTHETIC CAMERA TEST',24,44);
Object.defineProperty(navigator,'mediaDevices',{configurable:true,value:{getUserMedia:async()=>{
  const stream=fixtureCanvas.captureStream(10),track=stream.getVideoTracks()[0];
  let frame=0;const timer=setInterval(()=>{fixtureContext.fillStyle=frame++%2?'#bfe0c4':'#d5e8d0';fixtureContext.fillRect(600,440,20,20);track.requestFrame?.();},100);
  const stop=track.stop.bind(track);track.stop=()=>{clearInterval(timer);stop();};return stream;
}}});
