// Camera stream only: never requests a microphone, network or another camera.
export const VIDEO = Object.freeze({ bytes: 8 * 1024 ** 2, seconds: 30, count: 3 });
export const videoType = value => String(value || '').split(';')[0].trim().toLowerCase();
export async function checkVideo(blob) {
  const b = new Uint8Array(await blob.slice(0, 12).arrayBuffer()), type = videoType(blob.type);
  if (blob.size > VIDEO.bytes || !blob.size || !(type === 'video/mp4' && String.fromCharCode(...b.slice(4, 8)) === 'ftyp' ||
      type === 'video/webm' && [26, 69, 223, 163].every((n, i) => b[i] === n)))
    throw new Error('Vælg en rigtig MP4- eller WebM-video på højst 8 MiB.');
}
export async function decodeVideo(blob, recordedSeconds) {
  await checkVideo(blob);
  const video = document.createElement('video'), url = URL.createObjectURL(blob);
  video.muted = true; video.playsInline = true; video.preload = 'auto';
  try {
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => finish(new Error('Videoen kunne ikke indlæses. Originalfilen er bevaret.')), 10000);
      const finish = error => { clearTimeout(timer); video.onloadeddata = video.onerror = null; error ? reject(error) : resolve(); };
      video.onloadeddata = () => finish();
      video.onerror = () => finish(new Error('Denne browser kan ikke afspille videoens codec. Originalfilen er bevaret.'));
      video.src = url; video.load();
    });
    const duration = Number.isFinite(video.duration) && video.duration > 0 ? video.duration : recordedSeconds;
    if (!Number.isFinite(duration) || duration <= 0 || duration > VIDEO.seconds + 0.5 ||
        !video.videoWidth || !video.videoHeight || Math.max(video.videoWidth, video.videoHeight) > 3840)
      throw new Error('Vælg en video på højst 30 sekunder og 3840 pixels. Ukendt varighed kan ikke importeres uden optagelsesdata.');
    return { width: video.videoWidth, height: video.videoHeight, duration };
  } finally { video.pause(); video.removeAttribute('src'); video.load(); URL.revokeObjectURL(url); }
}
export class VideoRecorder {
  constructor({ Recorder = globalThis.MediaRecorder, seconds = VIDEO.seconds, maxBytes = VIDEO.bytes, onState = () => {} } = {}) {
    this.Recorder = Recorder; this.seconds = seconds; this.maxBytes = maxBytes; this.onState = onState; this.state = 'idle';
  }
  get supported() { return typeof this.Recorder === 'function'; }
  start(stream) {
    if (this.state !== 'idle') throw new Error('Der optages allerede.');
    if (!this.supported) throw new Error('Livevideo understøttes ikke her. Brug Vælg video i stedet.');
    if (!stream?.getVideoTracks().some(t => t.readyState === 'live') || stream.getAudioTracks().length)
      throw new Error('Start kameraet uden lyd, før du optager video.');
    const mimeType = ['video/mp4', 'video/webm;codecs=vp8', 'video/webm'].find(t => this.Recorder.isTypeSupported?.(t));
    const recorder = new this.Recorder(stream, { ...(mimeType ? { mimeType } : {}), videoBitsPerSecond: 1500000 });
    const chunks = []; let bytes = 0, error, done = false;
    this.recorder = recorder;
    const started = performance.now();
    const result = new Promise((resolve, reject) => {
      const finish = () => {
        if (done) return; done = true; clearTimeout(this.timer); clearTimeout(this.watchdog);
        for (const t of stream.getVideoTracks()) t.removeEventListener('ended', ended);
        this.state = 'idle'; this.recorder = null; this.onState('idle');
        const blob = new Blob(chunks, { type: recorder.mimeType || chunks[0]?.type });
        if (error || !blob.size) reject(error || new Error('Optagelsen indeholdt ingen video. Prøv igen.'));
        else resolve({ blob, duration: Math.min(this.seconds, (performance.now() - started) / 1000) });
      };
      const ended = () => this.stop();
      for (const t of stream.getVideoTracks()) t.addEventListener('ended', ended, { once: true });
      recorder.ondataavailable = event => {
        if (done || !event.data?.size) return;
        if (bytes + event.data.size > this.maxBytes) {
          error = new Error('Videoen overskred 8 MiB og blev ikke gemt. Optag et kortere klip.'); chunks.length = 0; this.stop();
        } else if (!error) { chunks.push(event.data); bytes += event.data.size; }
      };
      recorder.onerror = () => { error = new Error('Videooptagelsen blev afbrudt af browseren. Eksisterende projekter er bevaret.'); this.stop(); };
      recorder.onstop = finish;
      this.finish = finish;
      this.fail = () => { error = new Error('Browseren afsluttede ikke videoen. Klippet kunne ikke gemmes; tidligere projekter er bevaret.'); finish(); };
      try { recorder.start(250); this.state = 'recording'; this.onState('recording'); this.timer = setTimeout(() => this.stop(), this.seconds * 1000); }
      catch (cause) { error = cause; finish(); }
    });
    // A result may reject before the UI has attached its handler.
    result.catch(() => {}); return result;
  }
  stop() {
    if (this.state !== 'recording') return;
    this.state = 'stopping'; this.onState('stopping'); clearTimeout(this.timer);
    this.watchdog = setTimeout(() => this.fail(), 5000);
    if (this.recorder.state !== 'inactive') { try { this.recorder.stop(); } catch { this.fail(); } }
  }
}
