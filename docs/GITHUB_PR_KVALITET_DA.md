# Scan3D · GitHub-kvalitet og sikkerhed
Opdateret 26. oktober 2026. Denne fil beskriver den aktuelle, verificerede PR-kæde.

## Aktuelle pull requests
- **PR #1** `codex/sync-scan3d` → `main`: native scanner med MetalKit-resultatviewer. Draft. Grøn CI på head `0a3692202d91304538ee25029ddb24ed1f1a1e40`, [run 40213359599](https://github.com/cliffdkp1990/scan3d-lidar-native/actions/runs/40213359599).
- **PR #6** `ci/scan3d-doctor-current-metal-20261025` → `codex/sync-scan3d`: CI-rapportering, preflight, regressionstests og Scan3D Doctor, uden Swift-ændringer. Draft. Seneste grønne CI på head `3c01eac9450dd1469d0cd72c0ae8db1bc85b180c`, [run 40254758553](https://github.com/cliffdkp1990/scan3d-lidar-native/actions/runs/40254758553).
- **PR #2, #3, #4 og #5 er lukket uden merge.** Deres historik er bevaret. Den gamle RealityKit-renderer må ikke genindføres oven på MetalKit-vieweren.

Begge aktive PR'er er stadig draft. Ingen merge, deploy, TestFlight eller installation udføres automatisk.

## Aktiv beskyttelse af main
Ruleset **Scan3D main protection** (id `25845419`) er verificeret som `active`, målrettet `refs/heads/main`, uden bypass-aktører:
- PR påkrævet, 0 obligatoriske reviewer-godkendelser
- Krævet check: `Test and compile actual repository source`
- Forbud mod force-push (`non_fast_forward`) og sletning (`deletion`)

[Se GitHub Rules](https://github.com/cliffdkp1990/scan3d-lidar-native/settings/rules).

## CI-resultater skal forstås præcist
- GitHub tester normalt et genereret PR-merge-commit. Rapporten gemmer både faktisk checkout-SHA og branch-head-SHA. Grønt PR-merge-build er ikke dokumentation for et separat standalone-head-build.
- Kontrollér altid sidste CI-kørsel efter den seneste ændring. Gamle grønne kørsler kan ikke godkende ny kode.
- Preflight og Python-regressionstests, kilde-/videotests, native UI-tests, Debug Simulator, Release Simulator og usigneret iOS-device-build er separate kontroller.
- Ændringer i `Scan3DLiDAR/**`, `scripts/**` og begge relevante workflowfiler starter også kontrol ved push til `main`. Alle PR'er testes uanset ændrede stier.
- Xcode- og Simulator-tests bruger syntetiske fixture-data; de erstatter **ikke** en fysisk iPhone 14 Pro Max LiDAR-/kameratest. Et usigneret iOS-build kan ikke installeres på telefonen.
- Der kan ikke loves 3D-printparat rekonstruktion, TestFlight eller Apple-signering før de er separat bygget og afprøvet.

## Valgfri, gratis iPhone-installationsvej (forberedt i draft PR #6)
**Status: KUN forberedt og først tilgængelig efter grøn CI på denne nye ændring.**

For at undgå krav om betalt Apple Developer Program og lokal Mac kan den eksisterende GitHub macOS-CI pakke den allerede beståede **usignerede** Release-device-app som `Scan3D-unsigned-local-test.ipa`. Artefaktet produceres **kun for en pull request efter at alle seks kvalitetsgates er grønne**. Det gemmes i 7 dage med SHA-256 og både PR-head-SHA og testet checkout-SHA, under navnet `scan3d-unsigned-ipa-<PR-head-SHA>`.

Et IPA-arkiv er kun en ZIP med `Payload/Scan3DLiDAR.app`; det er **ikke Apple-signeret** og kan ikke installeres direkte ved at åbne det i iOS. En uafhængig lokal signeringsproces er nødvendig. På Windows kan brugeren frivilligt benytte eksempelvis [Sideloadly](https://sideloadly.io/) eller [AltStore Classic](https://altstore.io/) med sin egen Apple-konto. Det er **tredjepartsværktøjer**; gennemgå deres betingelser/sikkerhed og indtast aldrig kodeord eller tofaktorkoder i GitHub, ChatGPT, et issue eller en delt buildfil. Krav om USB/parkobling og Developer Mode kan gælde; følg værktøjets anvisninger.

**Gratis Apple Personal Team-profiler varer normalt 7 dage** og kræver periodisk fornyelse via Windows. Denne fremgangsmåde er en privat, valgfri fysisk test og kan ikke erstatte rigtig TestFlight- eller App Store-signering. Der er endnu **ingen bekræftet installation eller virkelig LiDAR-test**. Apple-udviklermedlemskab er stadig ikke verificeret. Filer og originale optagelser bør sikkerhedskopieres før opdateringer af appen.

Brug kun IPA-artefakter fra det **kendte** Scan3D-repository og en præcis grøn PR-CI-kørsel, ikke fra ukendte pull requests. Der oprettes ingen release, auto-installation, signeringsnøgler eller Apple-upload som del af CI.

Officielt: [Apple om gratis Personal Team og syv-dages gyldighed](https://developer.apple.com/help/account/basics/about-your-developer-account); [Apple om betatest og TestFlight](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases).

## Næste kontrollerede trin
1. Gennemgå PR #1's MetalKit/kamera- og datalagringskode og de faktiske CI-artefakter.
2. Gennemgå PR #6's privilegerede Doctor-workflow (`actions:write`, `issues:write`) og dokumentér godkendelsen.
3. Lav fysisk prøve af kamera, dybde, gemte PLY/OBJ-filer, videofunktion, brugervenlighed i portrait/landscape og iOS-installation.
4. **Kun efter særskilt beslutning:** integrér PR #1 før PR #6. Ingen automatisk merge. Doctor-workflowets `workflow_run` bliver først aktivt, når workflowfilen ligger på default branch `main`.
