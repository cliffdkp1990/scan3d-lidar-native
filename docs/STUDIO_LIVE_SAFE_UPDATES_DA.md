# Scan3D Studio: sikker kildegenskabelse og opdatering

## Nuværende sikre løsning

Åbn webappen fra **https://scan3d-studio-cliff.vercel.app**. Ingen ny ZIP/IPA eller gentaget login for browserudgaven. Dette arbejde ændrer **ikke** din installerede PWA, Vercel-production, `main` eller eksisterende scanninger.

## Verificeret offentlig kilde (28. oktober 2026)

- Startside `/index.html`: HTTP 200; SHA-256 `9a790775bb38cb5cf4004a31c711834ca558338103eb25d2ec5380fff22a22d1`.
- Manifest `/manifest.webmanifest`: HTTP 200; SHA-256 `cb03bc38e8dce52301ad96419dc3425dc4cab053fb7261c6fd8bc7fa4077ef55`.
- Service-worker `/sw.js`: HTTP 200; SHA-256 `1e67705b53780b6dae90e14615fc0d76259f34f15fcdc5b31dc21678270d0278`.
- Workerens `const CACHE='scan3d-atelier-v16'` og `caches.match(request)` betyder, at eksisterende JS/CSS kan fortsætte fra cache uden netværkskontrol, indtil service-workerens cache-nøgle/opdatering ændres. Den aktuelle produktionsfejl er dog ikke bevist på fysisk iPhone.

## Kode i denne branch

1. `tools/pwa/recover-public-atelier.mjs` henter alene offentligt tilgængelige same-origin static assets, som den faktisk auditerede `sw.js` selv angiver. Den kræver korrekt SHA-256 før og efter hentning, afviser redirects, API/private paths, ukendte filer, farlige stier og overdrevne filstørrelser. Den skriver kontrolkvittering med per-fil-SHA-256. **Det er ikke et komplet Git-/serverkildeprojekt, kun en dokumenteret statisk kopi af den offentlige deployment.**
2. `tools/pwa/prepare-studio-update.mjs` bygger en **separat ikke-deployeret kandidat** fra de verificerede byte-for-byte originaler, med ændringer kun i `sw.js`, `studio.html`, `index.html` og én ny `studio-safe-updates.js`. Alle øvrige billeder, 3D-modeller, JS, CSS og `manifest.webmanifest` bevares uændret.
3. Ny SW bruger network-first på statiske HTML/JS/CSS/manifest, med offline-fallback. Kun kendte ressourcer caches; projektfiler, API-kald og andre URL'er fanges ikke. Der er **ingen `skipWaiting()`**, så en aktiv app/optagelse ikke genstartes automatisk. Ved lukning af gamle vinduer kan browseren aktivere den ventende version. En lille, passiv hjælp kontrollerer for opdateringer ved genåbning/forgrund, uden `location.reload`.
4. `tools/pwa/studio-audit.test.mjs` og `.github/workflows/scan3d-studio-source-review.yml` kører selvstændige sikkerhedstests og forbereder en dokumenteret, **udelukkende intern GitHub Actions review-artifact**, ikke en fil brugeren skal hente til iPhone.

## Før produktion

- GitHub-kontroller grønne på eksakt branch-SHA med et fuldt bytebevis.
- Original PWA-scope, manifest og bibliotek kan genåbnes uændret. Opdateringsadfærden skal fysisk testes på iPhone (særligt offline → online, aktiv optagelse og gemt projekt).
- Den egentlige Vercel Studio-kilde og deploymentsintegration skal forbindes ordentligt. Den offentlig statiske kopi er ikke en garanti for, at byggekæden bag Studio er identisk.
- Ingen merge eller deployment uden særskilt, tydelig godkendelse. Forsøg ikke at automatisere Apple-login eller native LiDAR-signering på denne måde.

Sporing: [GitHub-opgave #26](https://github.com/cliffdkp1990/scan3d-lidar-native/issues/26). Safari-reviewkilden har separat [PR #27](https://github.com/cliffdkp1990/scan3d-lidar-native/pull/27), som blev flettet i funktionsgrenen, ikke i `main` og ikke i live Studio.
