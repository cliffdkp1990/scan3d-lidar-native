// Passive checks only. Permissions are never granted or requested by these helpers.
export function launchContext({userAgent='',platform='',maxTouchPoints=0,standalone=false}={}) {
  const ios=/iPhone|iPad|iPod/.test(userAgent)||(platform==='MacIntel'&&maxTouchPoints>1);
  return {ios,chromeIOS:ios&&/CriOS\//.test(userAgent),standalone:Boolean(standalone)};
}
export function cameraChecks({secure,mediaAvailable,policyAllowed,permission='unknown',framed=false}) {
  return [
    {label:'Sikker forbindelse',value:secure?'HTTPS er aktiv':'Åbn appens HTTPS-adresse',ok:Boolean(secure)},
    {label:'Browserkamera',value:mediaAvailable?'Kamerafunktionen findes':'Browseren stiller ikke kamera til rådighed',ok:Boolean(mediaAvailable)},
    {label:'Sidens kameraregel',value:policyAllowed===false?'Kamera er blokeret af sidens eller rammens regel':policyAllowed===true?'Kamera er tilladt af sidens regel':'Reglen kan ikke aflæses her',ok:policyAllowed!==false},
    {label:'Kameratilladelse',value:({granted:'Tilladt af browseren; iOS kan stadig blokere',denied:'Blokeret. Ret tilladelsen i browseren eller iPhone-indstillinger',prompt:'Du bliver spurgt, når du trykker Start kamera',unknown:'Kan ikke aflæses. Tryk Start kamera for at spørge'})[permission]||'Kan ikke aflæses',ok:permission!=='denied'},
    {label:'Åbning',value:framed?'Åbnet i et indlejret vindue. Brug den direkte appadresse':'Åbnet som egen side',ok:!framed}
  ];
}
