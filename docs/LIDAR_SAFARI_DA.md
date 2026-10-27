# Automatisk projektbro fra native LiDAR til Safari

Den eksisterende native Swift/ARKit-scanner aktiverer allerede dybde og understøttet mesh automatisk, når dens kamera starter på en kompatibel enhed. Denne ændring kobler de gemte modeller til Safari-projektformatet. Den tilføjer ikke sensoradgang til Safari, automatisk fotogrammetri eller en cloudtjeneste.

## På iPhone efter installation af native-appen

1. Scan i den native Scan3D-app på en LiDAR-kompatibel iPhone. Den kontrollerer ARKit-understøttelse ved kørsel. Godkendte optagelser gemmer en kumulativ PLY-punktsky; OBJ eksporteres med den eksisterende mesh-knap.
2. Åbn **Resultat** eller et projekt i **Mine scanninger**. Den senest gemte model klargøres automatisk som `.scan3d.json`. Nyere punktsky vælges frem for et ældre mesh; et efterfølgende mesh vinder igen.
3. Vælg **Del Safari-projektfil → Gem i Filer**. Åbn den separate webversion, og vælg **Importér projekt** og filen. Den eksisterende import opretter et nyt projekt med modelvisning og originaleksport. Den overskriver ikke andre projekter.

Der er stadig to bevidste overførselstrin: OS-deling og valg af fil i webappen. Appene har separate sandkasser; denne version kan hverken installere/signere sig selv eller overføre data ved skjult upload. Intet projekt sendes til en server. Der er ikke oprettet en offentlig webadresse i denne ændring.

En almindelig iPhone 13 har ingen LiDAR-scanner. En viewport mærket iPhone 13 dokumenterer kun et layout. Den native app kræver installation/signering ad en særskilt godkendt vej. Ingen Apple-signering, installation, merge, deployment eller udgivelse er udført her.

## Hvad der automatiseres

`SafariProjectShare` starter en annullerbar baggrundsopgave, når et gemt resultat vises. `SafariProjectArchive` kontrollerer registrering i det native projekt, almindelig fil uden symlink, størrelsesbegrænset læsning, SHA-256, geometri og de eksisterende webgrænser. En midlertidig, indholdsadresseret kopi klargøres og læses tilbage inden deling. Gentagne åbninger genbruger filnavnet. Delingen kræver fortsat brugerens tryk.

Webgrænser: 8 MiB originalmodel, 200.000 kildemodelpunkter og 60.000 trekanter; ASCII XYZ PLY eller trekantet OBJ uden materialer. Overskridelser giver en forklaring og bevarer den eksisterende deling af originalmodellen. Koordinater, meter og modelbytes ændres ikke. Webvisningens normalisering gælder kun visningen; der påstås ikke kalibreret opmåling.

Arkivet genbruger præcis `scan3d-safari-project` v2. Det indeholder kun den valgte model, titel og datoer. **Fotos, video og historik overføres ikke**, men bliver urørte i native-projektet. Det er en modelkopi, ikke en komplet native-backup. Originale manifests, billeder, videoer og geometri ændres ikke. Simulatorens modeller mærkes `demo`, aldrig målte LiDAR-data.

## Test, som CI faktisk skal gennemføre

Det eksisterende native workflow er uændret: source-tests, native billed-/UI-tests, Debug- og Release-Simulator-build, usigneret device-build og det eksisterende usignerede iPhone-pakketrin. En ny native UI-test kontrollerer automatisk klargøring og ærlig mærkning af syntetiske data.

Det nye read-only workflow `.github/workflows/scan3d-lidar-bridge.yml`:

- Kompilerer og kører selve Swift-eksporteren med `ProjectStore`, `GeometryExport` og `GeometryPreview` på macOS. Afprøver hashfejl, korrupte filer, forkert projekt, modelvalg, grænser, Unicode-titler og bevaring af originalerne.
- Producerer PLY/OBJ og v2-arkiver med den faktiske Swift-kode, ikke en separat JavaScript-efterligning. Producenten registrerer checkout, run-ID og SHA-256 for alle fixtures.
- Importerer de producerede arkiver med den eksisterende JavaScript-importør, laver backup/genimport og sammenholder alle modelbytes.
- Kører alle eksisterende webtests samt tre ekstra WebKit-forløb i 390 × 844, 844 × 390 og 1480 × 910. Hvert forløb importerer både Swift-PLY og -OBJ, genåbner fra IndexedDB, downloader originalerne og afviser en beskadiget kopi uden at ændre gemte projekter.
- Skriver `TESTED_COMMIT.json` med præcis checkout/PR-head og faktiske testresultater. Artefakter indeholder kun syntetiske fixtures og screenshots og opbevares i 7 dage. Ingen retries eller deploymenttrin.

Listen ovenfor beskriver testkravene. Den konkrete PR-beskrivelse og de tilknyttede Actions-kørsler er kvitteringen for, hvilke commits og trin der faktisk bestod. Der påstås ikke fysisk LiDAR-test, iPhone-installation, Safari-app, touch, kamera, OS-deling eller Gem i Filer uden sådan efterprøvning.

## Kontrolleret teknisk grundlag

- Apple: [supportsFrameSemantics](https://developer.apple.com/documentation/arkit/arconfiguration/supportsframesemantics(_:)) skal kontrolleres på den konkrete ARWorldTrackingConfiguration før aktivering af dybde.
- Apple: [sceneDepth](https://developer.apple.com/documentation/arkit/arconfiguration/framesemantics-swift.struct/scenedepth) stammer fra LiDAR og kræver en kompatibel enhed.
- Apple: [sceneReconstruction](https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration/scenereconstruction) kræver kontrol af mesh-understøttelse.

ARKit-konfiguration, automatisk foto/video, sensorbehandling, kameraadgang, samtlige eksisterende workflows og projektets signeringsindstillinger er bevaret. Integrationen ligger separat oven på web-PR #9 og ændrer ikke tidligere PR-heads eller main-beskyttelsen.
