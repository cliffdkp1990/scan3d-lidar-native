# Scan3D Studio · native beta – leveringskontrol

Dato: 21. november 2026. **Arbejdsdokument, ingen installerbar beta eller fysisk test godkendt endnu.**

Dette dokument udløser en fuld native iOS-build på PR #25, fordi main har et
påkrævet `Test and compile actual repository source`-check. Et Windows-only
tjek er **ikke nok** til en iPhone-beta. Branch-beskyttelsen må ikke omgås.

## Første beta: smalt omfang

- iPhone 14 Pro Max med rigtig LiDAR: lås mål, optag automatiske fotos / valgfri video og saml punktsky.
- Gem fotos, video og PLY/OBJ som originalfiler i projektbiblioteket. Åbn gemt 3D-resultat.
- Kamera på pause kræver ny mål-låsning ved genstart; tidligere gemte filer må ikke mistes.
- Ingen løfter om målenøjagtighed i millimeter, printklar STL, automatisk modelreparation eller video-til-3D.

## Beta-gates (vær ærlig om status)

1. GitHub Actions på **aktuel PR-head SHA**: kildekode-, simulator-, native UI- og Release-iPhone-build alle bestået.
2. `scan3d-unsigned-iphone` artifact med ægte arm64 iOS-Release-app, SHA-256 og `SCAN3D_PACKAGE.json`.
3. Efter en godkendt main-merge: frisk grønt main-build og `scan3d-newest-green-main-unsigned` fra PR #25 installer-workflowet.
4. Underskriv/sideload på brugerens egen iPhone med egen Apple-konto; bekræft installation, tilladelser og faktisk opstart.
5. Fysisk prøvescanning, fil-integritetskontrol, genåbning, PLY/OBJ-deling, afbrydelser, batteri og varme testet. Registrer præcis SHA og iOS-version.

**Ingen beta må kaldes 'installeret', 'fysisk testet' eller 'printklar' blot fordi CI er grøn.**
Undlad at slette gamle Scan3D-projekter, ændre Apple-sikkerhedsindstillinger på brugerens vegne eller flytte scanninger til cloud uden brugerens valg.

## Brug GitHub-appen på iPhone

Repository `cliffdkp1990/scan3d-lidar-native` → **Pull requests** → **#25**
(installationspakke) og **#32** (korrekt pause/genstart). Følg **Checks** og
**Actions**. GitHub mobilapp viser ikke nødvendigvis alle downloadmuligheder
for CI-artefakter; download af IPA kræver eventuelt Windows eller en browser
som et særskilt installationsskridt.

Denne fil indeholder ingen passwords, certifikater, personlige data eller kodeændringer.
