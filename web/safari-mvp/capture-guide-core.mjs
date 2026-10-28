export const CHOICE_KEY = 'scan3d-capture-guide-v1';
export const PLANS = Object.freeze({
  room: Object.freeze({name:'Mit rum', title:'Rundt i rummet', steps:Object.freeze([
    ['Find en rolig start', 'Start i et hjørne med godt lys og tydelige detaljer.'],
    ['Bevæg dig langsomt', 'Lad nabobilleder vise noget af det samme. Tag også gulv og vægge med.'],
    ['Se efter huller', 'Gå tilbage til områder, du mangler. Glas, spejle og bevægelse kan give problemer.']
  ])}),
  object: Object.freeze({name:'Min genstand', title:'Hele vejen rundt', steps:Object.freeze([
    ['Hold motivet stille', 'Brug jævnt lys og en genstand med synlige detaljer. Undgå blanke flader.'],
    ['Gå rundt om motivet', 'Tag overlappende billeder fra flere sider. Flyt telefonen, og lad motivet stå.'],
    ['Husk top og sider', 'Prøv en højere og en lavere vinkel. Se billederne igennem, før du stopper.']
  ])})
});
const validId = id => typeof id === 'string' && /^[a-zA-Z0-9-]{1,80}$/.test(id);
export const validMode = mode => typeof mode === 'string' && Object.hasOwn(PLANS, mode);
export function parseChoices(text) {
  try {
    const value = JSON.parse(text);
    if (value?.version !== 1 || !Array.isArray(value.choices)) return [];
    const entries = new Map();
    for (const entry of value.choices.slice(-40)) {
      if (Array.isArray(entry) && entry.length === 2 && validId(entry[0]) && validMode(entry[1])) entries.set(entry[0], entry[1]);
    }
    return [...entries];
  } catch { return []; }
}
export function rememberChoice(choices, id, mode) {
  if (!validId(id) || !validMode(mode)) throw new Error('Vælg rum eller genstand i et åbent projekt.');
  return [...choices.filter(([key]) => key !== id), [id, mode]].slice(-40);
}
export function captureSummary(project) {
  if (!project) return 'Vælg dit motiv. Dit første projekt oprettes, når du vælger.';
  const photos = project.photos.length, videos = (project.videos || []).length;
  return photos+' '+(photos === 1 ? 'foto' : 'fotos')+' · '+videos+' '+(videos === 1 ? 'video' : 'videoer')+' · '+(project.model ? 'model tilføjet' : 'ingen 3D-model endnu');
}
