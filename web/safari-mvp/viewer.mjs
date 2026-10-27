import { GEOMETRY_LIMITS } from './geometry.mjs';
const clamp = (n,a,b) => Math.max(a, Math.min(b,n));
export class ModelViewer {
  constructor(canvas, onChange = () => {}) {
    this.canvas = canvas; this.onChange = onChange; this.geometry = null; this.pointers = new Map(); this.distance = 0;
    this.view = { yaw: -.45, pitch: .18, zoom: 1 }; this.frame = 0; this.resources = [];
    this.gl = canvas.getContext('webgl', { alpha: true, antialias: true, depth: true, preserveDrawingBuffer: false });
    canvas.addEventListener('webglcontextlost', event => { event.preventDefault(); canvas.dataset.state = 'lost'; this.onChange('3D-grafikken blev afbrudt. Originalen kan stadig eksporteres.'); });
    canvas.addEventListener('webglcontextrestored', () => { this.init(); if (this.geometry) this.setGeometry(this.geometry); });
    if (this.gl) this.init(); else { canvas.dataset.state = 'unsupported'; this.onChange('WebGL er ikke tilgængeligt. Originalen kan stadig gemmes og eksporteres.'); }
    this.resize = new ResizeObserver(() => this.schedule()); this.resize.observe(canvas);
    canvas.addEventListener('pointerdown', e => { this.pointers.set(e.pointerId,[e.clientX,e.clientY]); canvas.setPointerCapture(e.pointerId); this.distance = 0; });
    canvas.addEventListener('pointermove', e => {
      const old = this.pointers.get(e.pointerId); if (!old) return;
      this.pointers.set(e.pointerId,[e.clientX,e.clientY]);
      if (this.pointers.size === 1) { this.view.yaw += (e.clientX-old[0])*.012; this.view.pitch = clamp(this.view.pitch+(e.clientY-old[1])*.008,-1.3,1.3); }
      else if (this.pointers.size === 2) { const [a,b] = [...this.pointers.values()], d = Math.hypot(a[0]-b[0],a[1]-b[1]); if (this.distance > 0) this.view.zoom = clamp(this.view.zoom*d/this.distance,.5,2.5); this.distance = d; }
      this.schedule();
    });
    for (const event of ['pointerup','pointercancel','lostpointercapture']) canvas.addEventListener(event,e => { this.pointers.delete(e.pointerId); this.distance = 0; });
  }
  init() {
    const gl = this.gl; this.release();
    const vertex = `attribute vec3 position; attribute vec3 normal; uniform vec3 view; uniform float aspect; uniform float pointSize; varying float light;
      void main(){float cy=cos(view.x),sy=sin(view.x),cp=cos(view.y),sp=sin(view.y);
      mat3 r=mat3(cy,0.,-sy,0.,1.,0.,sy,0.,cy); mat3 p=mat3(1.,0.,0.,0.,cp,sp,0.,-sp,cp);
      vec3 v=p*r*position; vec3 n=p*r*normal; light=length(n)>.1?.65+.35*abs(dot(normalize(n),normalize(vec3(-.4,.7,1.)))):1.;
      gl_Position=vec4(v.x*view.z/aspect,v.y*view.z,-v.z*.25,1.); gl_PointSize=pointSize;}`;
    const fragment = `precision mediump float; varying float light; void main(){gl_FragColor=vec4(vec3(.16,.68,.56)*light,1.);}`;
    const shader = (type,code) => { const s = gl.createShader(type); gl.shaderSource(s,code); gl.compileShader(s); if (!gl.getShaderParameter(s,gl.COMPILE_STATUS)) { gl.deleteShader(s); throw new Error('3D-grafikken kunne ikke kompileres.'); } this.resources.push(['shader',s]); return s; };
    const program = gl.createProgram(); this.resources.push(['program',program]); gl.attachShader(program,shader(gl.VERTEX_SHADER,vertex)); gl.attachShader(program,shader(gl.FRAGMENT_SHADER,fragment)); gl.linkProgram(program);
    if (!gl.getProgramParameter(program,gl.LINK_STATUS)) throw new Error('3D-grafikken kunne ikke startes.');
    this.program = program; this.position = gl.getAttribLocation(program,'position'); this.normal = gl.getAttribLocation(program,'normal');
    this.viewUniform = gl.getUniformLocation(program,'view'); this.aspect = gl.getUniformLocation(program,'aspect'); this.pointSize = gl.getUniformLocation(program,'pointSize');
    this.buffer = gl.createBuffer(); this.resources.push(['buffer',this.buffer]);
  }
  release() { if (!this.gl) return; for (const [type,value] of this.resources) this.gl['delete'+type[0].toUpperCase()+type.slice(1)](value); this.resources = []; }
  setGeometry(geometry) {
    this.geometry = geometry; this.view = { yaw: -.45, pitch: .18, zoom: 1 };
    if (!this.gl) return;
    const values = [], points = geometry.normalized;
    if (geometry.isPointCloud) {
      const count = Math.min(points.length,GEOMETRY_LIMITS.displayPoints);
      for (let i=0;i<count;i++) values.push(...points[Math.floor(i*points.length/count)],0,0,0);
    } else for (const f of geometry.faces) {
      const [a,b,c] = f.map(i=>points[i]), u=b.map((n,i)=>n-a[i]),v=c.map((n,i)=>n-a[i]);
      const n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]];
      for (const p of [a,b,c]) values.push(...p,...n);
    }
    this.count = values.length/6; const gl = this.gl;
    gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer); gl.bufferData(gl.ARRAY_BUFFER,new Float32Array(values),gl.STATIC_DRAW); this.schedule();
  }
  clear() { this.geometry = null; if (this.gl) this.gl.clear(this.gl.COLOR_BUFFER_BIT|this.gl.DEPTH_BUFFER_BIT); this.canvas.dataset.state = this.gl ? 'empty' : 'unsupported'; }
  action(action) {
    if (action==='left') this.view.yaw-=Math.PI/6;
    if (action==='right') this.view.yaw+=Math.PI/6;
    if (action==='in') this.view.zoom=clamp(this.view.zoom*1.2,.5,2.5);
    if (action==='out') this.view.zoom=clamp(this.view.zoom/1.2,.5,2.5);
    if (action==='reset') this.view={yaw:-.45,pitch:.18,zoom:1};
    this.schedule();
  }
  schedule() { if (!this.frame) this.frame=requestAnimationFrame(()=>{this.frame=0;this.draw();}); }
  draw() {
    const gl=this.gl,c=this.canvas;if(!gl||!this.geometry||gl.isContextLost())return;
    const width=c.clientWidth,height=c.clientHeight;if(!width||!height)return;
    const ratio=Math.min(devicePixelRatio||1,2),w=Math.round(width*ratio),h=Math.round(height*ratio);if(c.width!==w||c.height!==h){c.width=w;c.height=h;}
    gl.viewport(0,0,c.width,c.height);gl.clearColor(0,0,0,0);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);gl.enable(gl.DEPTH_TEST);gl.useProgram(this.program);
    gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);gl.enableVertexAttribArray(this.position);gl.vertexAttribPointer(this.position,3,gl.FLOAT,false,24,0);gl.enableVertexAttribArray(this.normal);gl.vertexAttribPointer(this.normal,3,gl.FLOAT,false,24,12);
    gl.uniform3f(this.viewUniform,this.view.yaw,this.view.pitch,this.view.zoom*.9);gl.uniform1f(this.aspect,width/height);gl.uniform1f(this.pointSize,2.2*ratio);
    gl.drawArrays(this.geometry.isPointCloud?gl.POINTS:gl.TRIANGLES,0,this.count);
    c.dataset.state='ready';c.dataset.yaw=this.view.yaw.toFixed(3);c.dataset.zoom=this.view.zoom.toFixed(3);c.dataset.vertices=String(this.geometry.vertices.length);c.dataset.triangles=String(this.geometry.faces.length);
  }
}
