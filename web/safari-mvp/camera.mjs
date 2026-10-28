export function cameraMessage(error) {
  return ({ NotAllowedError: 'Kameraadgang blev afvist. Du kan stadig vælge et foto fra Filer eller Fotos.',
    NotFoundError: 'Intet kamera blev fundet. Vælg et foto i stedet.',
    NotReadableError: 'Kameraet er optaget eller utilgængeligt. Luk andre kameraapps, og prøv igen.',
    OverconstrainedError: 'Kameraet kan ikke bruge de ønskede indstillinger. Vælg et foto i stedet.' })[error?.name] ||
    'Kameraet kunne ikke startes. Åbn appens HTTPS-adresse i Chrome eller Safari. Vælg Kamera og hjælp, eller vælg et foto.';
}
export class CameraSession {
  constructor(video, mediaDevices = globalThis.navigator?.mediaDevices, onState = () => {}) {
    this.video = video; this.mediaDevices = mediaDevices; this.onState = onState; this.serial = 0; this.stream = null;
  }
  async start() {
    this.stop(); const serial = this.serial;
    if (!this.mediaDevices?.getUserMedia) throw new Error('Livekamera kræver HTTPS og en browser med kameraadgang. Vælg eller tag et foto nedenfor.');
    this.onState('pending');
    let stream;
    try {
      stream = await this.mediaDevices.getUserMedia({ audio: false, video: { facingMode: { ideal: 'environment' }, width: { ideal: 1920 }, height: { ideal: 1080 } } });
      if (serial !== this.serial) { stream.getTracks().forEach(t => t.stop()); return false; }
      this.stream = stream; this.video.srcObject = stream; await this.video.play();
      if (serial !== this.serial) { stream.getTracks().forEach(t => t.stop()); return false; }
      for (const track of stream.getVideoTracks()) track.addEventListener('ended', () => { if (serial === this.serial) this.stop(); }, { once: true });
      this.onState('active'); return true;
    } catch (error) {
      stream?.getTracks().forEach(t => t.stop());
      if (serial !== this.serial) return false;
      this.stop(); throw new Error(cameraMessage(error));
    }
  }
  stop() {
    this.serial++; this.stream?.getTracks().forEach(t => t.stop()); this.stream = null;
    this.video.pause(); this.video.srcObject = null; this.onState('stopped');
  }
}
export async function decodePhoto(blob) {
  const url = URL.createObjectURL(blob), image = new Image();
  try {
    image.src = url; await image.decode();
    if (!image.naturalWidth || !image.naturalHeight || image.naturalWidth * image.naturalHeight > 32_000_000) throw new Error('Fotoet overstiger grænsen på 32 megapixel.');
    return image;
  } finally { URL.revokeObjectURL(url); }
}
export async function jpegCopy(source, width, height) {
  if (!width || !height || width * height > 32_000_000) throw new Error('Billedet er tomt eller for stort.');
  const scale = Math.min(1, 1600 / width, 1600 / height), canvas = document.createElement('canvas');
  canvas.width = Math.max(1, Math.round(width * scale)); canvas.height = Math.max(1, Math.round(height * scale));
  const context = canvas.getContext('2d');
  if (!context) throw new Error('Browseren kan ikke behandle fotoet.');
  context.drawImage(source, 0, 0, canvas.width, canvas.height);
  const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/jpeg', .8));
  if (!blob) throw new Error('Fotoet kunne ikke kodes.');
  return { blob, width: canvas.width, height: canvas.height };
}
