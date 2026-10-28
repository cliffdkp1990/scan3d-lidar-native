// A single optional, non-disruptive PWA update path. No analytics or uploads.
// An update never reloads an unsaved project, ongoing camera or video session.
export function canSwitchPWA({busy=false,dirty=false,recording=false,
                              recovery=false,camera='stopped',depth='stopped'}={}) {
  return !busy&&!dirty&&!recording&&!recovery&&camera==='stopped'&&depth==='stopped';
}

export function initPWAUpdates({button,isSafe}) {
  if(!button||typeof isSafe!=='function')throw new TypeError('Update controls are required');
  if(!('serviceWorker' in navigator)||!window.isSecureContext) {
    button.hidden=true;
    return {refresh(){}};
  }
  let registration=null,requested=false,reloadPending=false,lastCheck=0;
  const show=()=>{
    const waiting=Boolean(registration?.waiting);
    const pending=waiting||reloadPending;
    const safe=Boolean(isSafe());
    button.hidden=!pending;
    button.disabled=!safe;
    if(pending)button.textContent=safe?'Ny version klar · Opdater app':'Ny version klar · Gem og stop først';
    button.title=(!safe&&pending)?'Gem projektet og stop kamera, video og dybdeforbindelse før opdatering':'';
  };
  const maybeReload=()=>{
    if(requested&&isSafe()){
      // Never automatically reload just because a new worker took control.
      requested=false;
      location.reload();
    }else{
      reloadPending=true;
      show();
    }
  };
  const examine=()=>{
    registration?.installing?.addEventListener('statechange',show);
    show();
  };
  async function check(){
    if(!registration||document.hidden||!navigator.onLine)return;
    const now=Date.now();
    if(now-lastCheck<60_000)return;
    lastCheck=now;
    try{await registration.update();}catch{/* offline should remain usable */}
    show();
  }
  button.addEventListener('click',()=>{
    if(!isSafe()){show();return;}
    if(reloadPending){requested=true;maybeReload();return;}
    if(!registration?.waiting)return;
    requested=true;
    registration.waiting.postMessage({type:'SCAN3D_ACTIVATE_WHEN_SAFE'});
    show();
  });
  navigator.serviceWorker.addEventListener('controllerchange',()=>{
    if(requested&&isSafe())maybeReload();
    else if(requested){reloadPending=true;show();}
  });
  document.addEventListener('visibilitychange',()=>{
    if(!document.hidden)void check();
  });
  window.addEventListener('focus',()=>void check());
  navigator.serviceWorker.register('./sw.js',{scope:'./',updateViaCache:'none'})
    .then(reg=>{
      registration=reg;
      reg.addEventListener('updatefound',examine);
      examine();
      void check();
    })
    .catch(()=>{button.hidden=true;});
  return {refresh:show};
}
