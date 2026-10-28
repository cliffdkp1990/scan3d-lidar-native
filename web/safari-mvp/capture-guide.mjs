import { CHOICE_KEY, PLANS, parseChoices, rememberChoice, captureSummary } from './capture-guide-core.mjs';

export class CaptureGuide {
  constructor(root) {
    this.root = root; this.entries = []; this.renderedMode = undefined; this.storageAvailable = true;
    try { this.entries = parseChoices(localStorage.getItem(CHOICE_KEY)); } catch { this.storageAvailable = false; }
  }
  select(id, mode) {
    this.entries = rememberChoice(this.entries, id, mode);
    try { localStorage.setItem(CHOICE_KEY, JSON.stringify({version:1, choices:this.entries})); }
    catch { this.storageAvailable = false; }
  }
  render(project, locked, dirty = false) {
    const mode = this.entries.find(([id]) => id === project?.id)?.[1] || null;
    const text = (selector, value) => { const node = this.root.querySelector(selector); if (node.textContent !== value) node.textContent = value; };
    this.root.dataset.selected = String(Boolean(mode));
    for (const button of this.root.querySelectorAll('[data-capture-mode]')) {
      button.disabled = locked;
      button.setAttribute('aria-pressed', String(button.dataset.captureMode === mode));
    }
    text('#capture-summary', captureSummary(project));
    text('#capture-choice-help', project ? 'Vælg en vejledning til dette projekt. Dine filer bevares, når du skifter.' : 'To enkle måder at begynde. Kameraet starter først, når du beder om det.');
    this.root.querySelector('#capture-steps').hidden = !mode;
    this.root.querySelector('#capture-next').hidden = !mode;
    text('#capture-next', dirty ? 'Projektet er endnu ikke gemt. Bevar fanen, og hent en sikkerhedskopi, hvis lageret ikke kan bruges.' : project?.model ? 'Du kan undersøge din model under 3D-model og fortsætte med fotos og video her.' : 'Projektet er klar. Brug Start kamera eller Vælg foto nedenfor. Fotos og video bliver ikke automatisk til 3D.');
    this.root.querySelector('#capture-storage-note').hidden = this.storageAvailable;
    if (mode === this.renderedMode) return;
    this.renderedMode = mode;
    text('#capture-step-title', mode ? PLANS[mode].title : 'Optagevejledning');
    const steps = this.root.querySelector('#capture-step-list'); steps.replaceChildren();
    if (mode) for (const [title, description] of PLANS[mode].steps) {
      const item = document.createElement('li'), strong = document.createElement('strong'), detail = document.createElement('span');
      strong.textContent = title; detail.textContent = description; item.append(strong, detail); steps.append(item);
    }
  }
}
