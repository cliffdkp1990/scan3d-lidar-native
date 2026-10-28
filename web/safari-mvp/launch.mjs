import {launchContext,cameraChecks} from './launch-core.mjs';
const $=s=>document.querySelector(s);
export function initLaunchHelp() {
  const display=matchMedia('(display-mode: standalone)'),context=()=>launchContext({userAgent:navigator.userAgent,platform:navigator.platform,maxTouchPoints:navigator.maxTouchPoints,standalone:display.matches||navigator.standalone});
  let installPrompt=null;
  function update() {
    const c=context();$('#launch-state').textContent=c.standalone?'Åbnet som app':'Åbnet i browser';
    $('#install-app').hidden=c.standalone;
    $('#install-instructions').textContent=c.ios?'I Chrome på iPhone: Tryk Del ved adressen → Føj til hjemmeskærm → Tilføj. Hvis “Åbn som webapp” vises, slå det til. Åbn derefter Scan3D-ikonet.':installPrompt?'Tryk Installér nedenfor, og bekræft i browserens vindue.':'I Chrome: Åbn menuen ⋮ → Cast, gem og del → Installér side som app, hvis punktet findes. Ellers brug Opret genvej og Åbn som vindue, hvis browseren tilbyder det.';
    $('#native-install').hidden=!installPrompt||c.ios;
    $('#permission-guide').textContent=c.ios?'På iPhone: Åbn Indstillinger → Apps → Chrome → Kamera, hvis kontakten vises. I Chrome kan du også trykke på kamerategnet ved adressen og ændre tilladelsen. Vend tilbage, og tryk Start kamera.':'I Chrome: Tryk på indstillingssymbolet ved adressen → Websiteindstillinger → Kamera → Tillad. Vend tilbage, og tryk Start kamera.';
  }
  async function diagnose() {
    let permission='unknown',policyAllowed;
    try{permission=(await navigator.permissions.query({name:'camera'})).state;}catch{}
    try{policyAllowed=(document.permissionsPolicy||document.featurePolicy)?.allowsFeature('camera');}catch{}
    const rows=cameraChecks({secure:isSecureContext,mediaAvailable:Boolean(navigator.mediaDevices?.getUserMedia),policyAllowed,permission,framed:window.top!==window});
    $('#permission-results').replaceChildren(...rows.map(row=>{const item=document.createElement('li'),strong=document.createElement('strong');strong.textContent=row.label+': ';item.append(strong,document.createTextNode(row.value));item.dataset.ok=String(row.ok);return item;}));
    $('#permission-note').textContent='Kontrollen ændrer ingen tilladelser. Start kamera beder kun om kamera; appen bruger ingen mikrofon, placering eller notifikationer.';
  }
  $('#install-app').addEventListener('click',()=>{update();$('#install-dialog').showModal();});
  $('#close-install').addEventListener('click',()=>$('#install-dialog').close());
  $('#camera-help').addEventListener('click',()=>{update();diagnose();$('#permission-dialog').showModal();});
  $('#close-permissions').addEventListener('click',()=>$('#permission-dialog').close());
  $('#check-permissions').addEventListener('click',diagnose);
  $('#native-install').addEventListener('click',async()=>{
    const prompt=installPrompt;if(!prompt)return;installPrompt=null;update();
    try{await prompt.prompt();const choice=await prompt.userChoice;$('#install-result').textContent=choice?.outcome==='accepted'?'Browseren har modtaget dit valg. Kontrollér, at ikonet er oprettet.':'Installation blev ikke bekræftet. Du kan bruge siden i Chrome.';}
    catch{$('#install-result').textContent='Browseren kunne ikke vise installation. Brug Chrome-menuen.';}
  });
  window.addEventListener('beforeinstallprompt',event=>{event.preventDefault();installPrompt=event;update();});
  window.addEventListener('appinstalled',()=>{installPrompt=null;$('#install-result').textContent='Browseren melder appen installeret. Åbn Scan3D-ikonet.';update();});
  display.addEventListener?.('change',update);
  window.addEventListener('scan3d:cameraerror',()=>{$('#camera-help').classList.add('needs-attention');$('#camera-help').textContent='Kamera blokeret? Få hjælp';});
  $('#copy-app-link').addEventListener('click',async()=>{
    const link=new URL('./',location.href).href;
    try{await navigator.clipboard.writeText(link);$('#install-result').textContent='Appadressen er kopieret. Åbn den i Chrome.';}
    catch{$('#app-address').hidden=false;$('#app-address').value=link;$('#app-address').focus();$('#app-address').select();$('#install-result').textContent='Hold på adressen, og vælg Kopiér.';}
  });
  update();
}
