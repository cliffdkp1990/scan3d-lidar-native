// Record3D's documented Wi-Fi RGBD format: left half HSV depth (3*hue m),
// right half colour. Protocol reference and MIT notice are in docs/CHROME_LIDAR_DA.md.
// This is an approximate single depth frame, never a fused or watertight model.
export const R3D = Object.freeze({maxJSON:262144,maxPixels:4_000_000,maxPoints:20000});
const bad=message=>{throw new Error(message);};
export function privateIPv4(value) {
  if(typeof value!=='string'||!/^\d{1,3}(?:\.\d{1,3}){3}$/.test(value))bad('Brug telefonens private IPv4-adresse, fx 192.168.1.40. Ingen URL eller port.');
  const p=value.split('.').map(Number);
  if(p.some((n,i)=>n>255||String(n)!==value.split('.')[i])||!(p[0]===10||p[0]===172&&p[1]>=16&&p[1]<=31||p[0]===192&&p[1]===168)||p[3]===0||p[3]===255)bad('Kun en privat Wi-Fi IPv4-adresse er tilladt.');
  return value;
}
export function videoOffer(raw,address) {
  privateIPv4(address);
  if(!raw||raw.type!=='offer'||typeof raw.sdp!=='string'||raw.sdp.length>R3D.maxJSON||!raw.sdp.startsWith('v=0'))bad('Telefonen leverede ikke et gyldigt WebRTC-videooffer.');
  const lines=raw.sdp.split(/\r?\n/),media=lines.filter(x=>x.startsWith('m='));
  if(media.filter(x=>/^m=video [1-9]/.test(x)).length!==1||media.some(x=>!/^m=video /.test(x)&&!/^m=\w+ 0 /.test(x)))bad('Kun én videostrøm uden lyd eller datakanal understøttes.');
  let candidates=0;
  const safe=lines.filter(line=>{
    if(!line.startsWith('a=candidate:'))return !line.startsWith('a=remote-candidates:');
    const t=line.trim().split(/\s+/);
    const accepted=t[4]===address&&t[6]==='typ'&&t[7]==='host'&&/^\d+$/.test(t[5])&&Number(t[5])>0&&Number(t[5])<=65535;
    if(accepted)candidates++;
    return accepted;
  });
  if(!candidates)bad('Record3D skal annoncere telefonens valgte IPv4-adresse som lokal host-kandidat.');
  return {type:'offer',sdp:safe.join('\r\n')};
}
export function calibration(metadata,width,height) {
  if(!Number.isInteger(width)||!Number.isInteger(height)||width<4||height<2||width%2||width*height>R3D.maxPixels)bad('RGBD-videoens størrelse er ugyldig eller for stor.');
  const k=metadata?.K,size=metadata?.originalSize;
  if(!Array.isArray(k)||k.length!==9||!k.every(Number.isFinite)||!Array.isArray(size)||size.length!==2||!size.every(n=>Number.isInteger(n)&&n>1&&n<=8192))bad('Record3D skal levere K og originalSize. Ukendte kameramål gættes ikke.');
  if(k[0]<1||k[4]<1||k[0]>1e6||k[4]>1e6||k[1]!==0||k[3]!==0||k[8]!==1)bad('Kameramatrixen er ikke understøttet.');
  let cx,cy;
  if(k[6]===0&&k[7]===0){cx=k[2];cy=k[5];}
  else if(k[2]===0&&k[5]===0){cx=k[6];cy=k[7];}
  else bad('Kameramatrixens layout er tvetydigt.');
  if(cx<=0||cx>=size[0]||cy<=0||cy>=size[1])bad('Kameraets hovedpunkt er uden for billedet.');
  const sx=(width/2)/size[0],sy=height/size[1];
  if(Math.abs(sx/sy-1)>.02)bad('RGBD-videoens format stemmer ikke med kamerametadata.');
  return {width,height,fx:k[0]*sx,fy:k[4]*sy,cx:cx*sx,cy:cy*sy};
}
export function pixelDepth(r,g,b) {
  r/=255;g/=255;b/=255;
  const hi=Math.max(r,g,b),lo=Math.min(r,g,b),d=hi-lo;
  if(!d||hi<.2||d/hi<.2)return NaN;
  let hue=hi===r?(g-b)/d:hi===g?(b-r)/d+2:(r-g)/d+4;
  hue=((hue/6)%1+1)%1;
  const z=3*hue;
  return z>=.1&&z<2.8?z:NaN;
}
export function framePLY(rgba,width,height,metadata) {
  const c=calibration(metadata,width,height);
  if(!(rgba instanceof Uint8ClampedArray)||rgba.length!==width*height*4)bad('RGBD-billedbufferen stemmer ikke med videomålene.');
  const half=width/2,step=Math.max(1,Math.ceil(Math.sqrt(half*height/R3D.maxPoints))),points=[];
  const depth=(x,y)=>{const p=(y*width+x)*4;return pixelDepth(rgba[p],rgba[p+1],rgba[p+2]);};
  pixels: for(let y=1;y<height-1;y+=step)for(let x=1;x<half-1;x+=step){
    const z=depth(x,y);if(!Number.isFinite(z))continue;
    let consistent=true;
    for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++){const n=depth(x+dx,y+dy);if(!Number.isFinite(n)||Math.abs(n-z)>.05)consistent=false;}
    if(!consistent)continue;
    points.push([((x-c.cx)*z/c.fx).toFixed(6),(-(y-c.cy)*z/c.fy).toFixed(6),(-z).toFixed(6)].join(' '));
    if(points.length>=R3D.maxPoints)break pixels;
  }
  if(points.length<3)bad('Der er for få sammenhængende dybdepunkter. Scan et tydeligt område i Record3D.');
  return 'ply\nformat ascii 1.0\ncomment Scan3D Record3D RGBD snapshot; sensor unverified; lossy depth; camera-relative meters; no fusion\nelement vertex '+points.length+'\nproperty float x\nproperty float y\nproperty float z\nend_header\n'+points.join('\n')+'\n';
}
