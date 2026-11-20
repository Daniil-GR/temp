/* A texture-mapped WebGL globe. No frameworks, network calls, or map services. */
(() => {
  'use strict';
  const canvas = document.querySelector('#earth-globe');
  if (!canvas) return;
  const scene = canvas.closest('.globe-scene');
  const fallback = scene.querySelector('[data-globe-fallback]');
  const pauseButton = scene.querySelector('[data-globe-pause]');
  const coordinates = scene.querySelector('[data-globe-coordinates]');
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)');
  let paused = reduceMotion.matches, longitude = -0.25, latitude = 0.22, zoom = 1;
  let dragging = false, lastX = 0, lastY = 0, visible = true, lastFrame = 0, frame = 0;
  let gl;
  try { gl = canvas.getContext('webgl', { alpha: true, premultipliedAlpha: false, antialias: true, powerPreference: 'low-power' }); } catch { /* image fallback */ }
  if (!gl) {
    canvas.hidden = true;
    scene.querySelector('.globe-controls').hidden = true;
    scene.querySelector('.globe-credit').textContent = 'Earth / NASA satellite imagery';
    return;
  }
  const vertex = `attribute vec2 position; varying vec2 uv; void main(){uv=position;gl_Position=vec4(position,0.,1.);}`;
  const fragment = `precision highp float;
    varying vec2 uv;uniform sampler2D earth;uniform float aspect;uniform float lon;uniform float lat;uniform float zoom;
    void main(){
      vec2 p=uv; p.x*=aspect;p/=0.79*zoom;
      float r=length(p);
      if(r>1.045){gl_FragColor=vec4(0.);return;}
      if(r>1.){float halo=pow(max(0.,1.-(r-1.)/.045),2.)*.23;gl_FragColor=vec4(.32,.65,.75,halo);return;}
      vec3 n=vec3(p.x,p.y,sqrt(max(0.,1.-dot(p,p))));
      float c=cos(lat),s=sin(lat);vec3 q=vec3(n.x,n.y*c+n.z*s,-n.y*s+n.z*c);
      c=cos(lon);s=sin(lon);q=vec3(q.x*c+q.z*s,q.y,-q.x*s+q.z*c);
      vec2 tex=vec2(atan(q.x,q.z)/6.2831853+.5,asin(clamp(q.y,-1.,1.))/3.14159265+.5);
      vec3 color=texture2D(earth,tex).rgb;
      float light=dot(n,normalize(vec3(-.65,.65,1.2)));
      color*=.31+.83*max(light,0.);
      color=mix(color,vec3(.21,.48,.60),pow(1.-n.z,3.)*.46);
      float gridLon=abs(fract(tex.x*24.+.5)-.5);float gridLat=abs(fract(tex.y*12.+.5)-.5);
      float grid=(1.-smoothstep(.0,.009,min(gridLon,gridLat)))*.075;
      color+=vec3(.55,.72,.70)*grid;
      gl_FragColor=vec4(color,(1.-smoothstep(.994,1.,r)));
    }`;
  function shader(type, source) {
    const item = gl.createShader(type); gl.shaderSource(item, source); gl.compileShader(item);
    if (!gl.getShaderParameter(item, gl.COMPILE_STATUS)) throw new Error('Globe shader compilation failed');
    return item;
  }
  let program;
  try {
    program = gl.createProgram(); gl.attachShader(program, shader(gl.VERTEX_SHADER, vertex));
    gl.attachShader(program, shader(gl.FRAGMENT_SHADER, fragment)); gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error('Globe link failed');
  } catch {
    canvas.hidden = true;scene.querySelector('.globe-controls').hidden = true;return;
  }
  gl.useProgram(program);
  const buffer = gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1,1,-1,-1,1,-1,1,1,-1,1,1]), gl.STATIC_DRAW);
  const position = gl.getAttribLocation(program,'position');gl.enableVertexAttribArray(position);gl.vertexAttribPointer(position,2,gl.FLOAT,false,0,0);
  const uniforms={};['aspect','lon','lat','zoom','earth'].forEach(k=>uniforms[k]=gl.getUniformLocation(program,k));
  const texture=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,texture);
  gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.REPEAT);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
  let ready=false;
  const image=new Image();image.onload=()=>{
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL,true);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGB,gl.RGB,gl.UNSIGNED_BYTE,image);
    gl.uniform1i(uniforms.earth,0);ready=true;fallback.hidden=true;canvas.dataset.ready='true';requestDraw();
  };
  image.onerror=()=>{canvas.hidden=true;scene.querySelector('.globe-controls').hidden=true;};
  image.src='assets/photos/earth-texture.jpg';
  function draw(now){
    frame=0;if(!ready||!visible||document.hidden){lastFrame=0;return;}
    if(!paused&&!dragging&&lastFrame)longitude+=Math.min(now-lastFrame,60)*.000035;
    lastFrame=now;
    const width=Math.round(canvas.clientWidth*Math.min(devicePixelRatio||1,1.7));const height=Math.round(canvas.clientHeight*Math.min(devicePixelRatio||1,1.7));
    if(canvas.width!==width||canvas.height!==height){canvas.width=width;canvas.height=height;gl.viewport(0,0,width,height);}
    gl.uniform1f(uniforms.aspect,width/height);gl.uniform1f(uniforms.lon,longitude);gl.uniform1f(uniforms.lat,latitude);gl.uniform1f(uniforms.zoom,zoom);
    gl.clearColor(0,0,0,0);gl.clear(gl.COLOR_BUFFER_BIT);gl.drawArrays(gl.TRIANGLES,0,6);
    const deg=((longitude*180/Math.PI)%360+540)%360-180;
    coordinates.textContent=Math.abs(deg).toFixed(1)+'° '+(deg<0?'W':'E');
    if(!paused&&!dragging)requestDraw();
  }
  function requestDraw(){if(!frame&&ready&&visible&&!document.hidden)frame=requestAnimationFrame(draw);}
  function setPause(value){paused=value;pauseButton.textContent=paused?'Play':'Pause';pauseButton.setAttribute('aria-label',paused?'Start globe rotation':'Pause globe rotation');lastFrame=0;requestDraw();}
  function changeZoom(delta){zoom=Math.max(.72,Math.min(1.4,zoom+delta));requestDraw();}
  canvas.addEventListener('pointerdown',event=>{if(event.button!==0)return;dragging=true;lastX=event.clientX;lastY=event.clientY;canvas.setPointerCapture(event.pointerId);canvas.focus({preventScroll:true});});
  canvas.addEventListener('pointermove',event=>{if(!dragging)return;longitude-=(event.clientX-lastX)*.006;latitude=Math.max(-1.3,Math.min(1.3,latitude+(event.clientY-lastY)*.005));lastX=event.clientX;lastY=event.clientY;requestDraw();});
  function release(){dragging=false;lastFrame=0;requestDraw();}
  canvas.addEventListener('pointerup',release);canvas.addEventListener('pointercancel',release);canvas.addEventListener('lostpointercapture',release);
  canvas.addEventListener('wheel',event=>{if(document.activeElement!==canvas)return;event.preventDefault();changeZoom(event.deltaY<0?.06:-.06);},{passive:false});
  canvas.addEventListener('keydown',event=>{let handled=true;switch(event.key){case 'ArrowLeft':longitude-=.15;break;case 'ArrowRight':longitude+=.15;break;case 'ArrowUp':latitude=Math.min(1.3,latitude+.12);break;case 'ArrowDown':latitude=Math.max(-1.3,latitude-.12);break;case '+':case '=':changeZoom(.1);break;case '-':changeZoom(-.1);break;case ' ':setPause(!paused);break;default:handled=false;}if(handled){event.preventDefault();requestDraw();}});
  scene.querySelector('[data-globe-left]').addEventListener('click',()=>{longitude-=.2;requestDraw();});
  scene.querySelector('[data-globe-right]').addEventListener('click',()=>{longitude+=.2;requestDraw();});
  scene.querySelector('[data-globe-zoom-in]').addEventListener('click',()=>changeZoom(.1));
  scene.querySelector('[data-globe-zoom-out]').addEventListener('click',()=>changeZoom(-.1));
  pauseButton.addEventListener('click',()=>setPause(!paused));setPause(paused);
  new ResizeObserver(()=>requestDraw()).observe(scene);
  new IntersectionObserver(entries=>{visible=entries[0].isIntersecting;lastFrame=0;requestDraw();},{threshold:0}).observe(scene);
  document.addEventListener('visibilitychange',()=>{lastFrame=0;requestDraw();});
  reduceMotion.addEventListener('change',event=>setPause(event.matches));
  canvas.addEventListener('webglcontextlost',event=>{event.preventDefault();ready=false;fallback.hidden=false;scene.querySelector('.globe-controls').hidden=true;});
})();
