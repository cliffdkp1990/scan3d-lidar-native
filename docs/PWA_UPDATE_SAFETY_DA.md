# Scan3D iPhone: opdater uden ZIP og uden at miste projekter

**Kodeændring:** `fix/safari-pwa-updates-preserve-captures-20261028`, baseret på `feature/chrome-home-screen`. Dette er **Safari-reviewwebappen** fra `web/safari-mvp`, **ikke** det separate, aktuelt deployede Vercel-projekt `scan3d-studio-cliff`.

## Hvad er ændret

- `web/safari-mvp/sw.js` precacher kun kendt, samme-origin skalkode (HTML, JS, CSS, manifest, ikoner). `fetch` er netværk-først for disse kendte filer, så genåbning online henter nyere JavaScript, selv om service-worker-versionen ikke er ændret. Offline bruges den sidst cachede skal.
- Projekters IndexedDB, localStorage, fotografier, video, PLY, OBJ, sikkerhedskopier og eksterne URL'er berøres ikke af workerens cache-logik; `activate` sletter kun ældre caches med dens eget `scan3d-safari-shell-`-præfiks.
- `pwa-updates.mjs` kontrollerer opdateringer, når siden bliver synlig eller får fokus. En ny, ventende service-worker vises som en knap på hjemmeskærms-webappen.
- **Ingen automatisk genstart.** Brugeren vælger selv opdatering, og den er kun tilgængelig, når ingen video optages, ingen fil er under gendannelse, ingen usikker kladde er åben, og kamera/RGBD-forbindelse er stoppet. Ved ny version, mens en optagelse kører, vises kun en deaktiveret `Gem og stop først`-knap.
- Førstegangsregistrering af service-worker og normal senere aktivering udløser ikke i sig selv en `location.reload()`.
- Den tidligere Chrome-only tekst er rettet, så Safari på iPhone viser korrekte trin til hjemmeskærmen. Ingen konto, ZIP eller IPA til **browserudgaven**.

## Afgrænsning

Dette beviser ikke, at `https://scan3d-studio-cliff.vercel.app` er opdateret. Dets Vercel-projekt `scan3d-studio-cliff` blev lavet fra uploadede kildefiler uden identificeret GitHub-link; det tilsyneladende relaterede GitHub-repository `cliffdkp1990/scan3d-studio-pro-max` er tomt. Denne rettelse er derfor klar til review i den separate Safari-webkilde, ikke klar til produktion i Atelier. Produktionskilden skal bevares og verificeres først, så ingen eksisterende scanninger eller ikonoplevelse bliver erstattet af en anden PWA.

Der er **ingen ændring af main, merge, Vercel-deployment, Apple-signering, telefoninstallering eller slettelse** i dette arbejde. Web-Safari får fortsat ikke ARKit sceneDepth fra iPhone LiDAR. Native LiDAR kræver stadig en signeret native app.

## Kontrol

`node --test web/safari-mvp/tests/pwa-updates.test.mjs` tester ændringer ved hvert hentet JS, fravær af interception af projekter/video, gamle kun-egen-caches og udtrykkelig same-origin opdateringsaktivering. Eksisterende webtests plus Playwright WebKit i telefonstørrelser skal også være grønne på præcis PR-head. Safari på en fysisk iPhone og offline/online-opdatering af den *rigtige* produktionsapp er **ikke** fysisk kontrolleret.

## Næste kritiske trin før produktionsrettelse

1. Få adgang til den fulde, originale source tree for Vercel-projektet `scan3d-studio-cliff`; bekræft checksum og metadata for alle filer, inklusive `src/sw.js`, `src/studio.html` og brugerens projektlager.
2. Gennemfør en separat, lille cache-/opdateringsrettelse i **netop den** kilde. Skift ikke app-id, manifest-scope eller IndexedDB-schema.
3. Test i preview og på fysisk iPhone, at en opdatering ikke lukker aktiv video eller ændrer gemte scanninger.
4. Udgiv kun efter klar godkendelse. Eksisterende produktionsalias må ikke omdirigeres automatisk.

Se også [Issue #26](https://github.com/cliffdkp1990/scan3d-lidar-native/issues/26).
