# Scan3D Native LiDAR · diagnosticering og automatiseringsplan

**27. oktober 2026.** Arbejdsdokument bundet til eksisterende iPhone/Swift/ARKit-kode. Ingen omdøbning, omskrivning af historiske filer, merge eller udrulning. iPhone 14 Pro Max er hovedenheden; Windows er kun installations-/signeringsassistent, ikke scanneren.

## Sandhedskilder og verificerede fund

1. **Native kilde:** `cliffdkp1990/scan3d-lidar-native`, `main` commit `1253d497d805cd17942b7892f4b484d753af3dd6` og native forbedring i PR #16. SwiftUI, ARKit, LiDAR-målinger, automatisk foto og video, lokal ProjectStore, Metal-resultatviewer og PLY/OBJ er allerede implementeret i koden. Koden er ikke bevis for fysisk iPhone-funktion.
2. **Ældre pakke:** `scan3d-unsigned-iphone` fra grønt macOS-run 40496124746. Indre `Scan3D-unsigned.ipa`: 1.115.948 byte, SHA-256 `b588c336facddfd5a4ef1ab4baaa5bab89306091716e9fa1552f450f28541fab`, buildkilde `1253d497...`. ZIP-manifestet verificerer filer og iPhone ARM64-platform. **Pakke er usigneret, ikke installeret, ikke nyere PR #16.**
3. **Faktisk fund i den byggede Info.plist:** `CFBundleVersion`, `CFBundleShortVersionString`, `UIFileSharingEnabled` og `LSSupportsOpeningDocumentsInPlace` var fraværende. Dermed kan installatør/versionering og synlighed af gemte Scan3D-projekter i iPhones Filer-app fejle. Dette er fund i faktisk IPA, ikke alene en teoretisk kontrolliste.
4. **Nyeste native CI:** commit `33d02c17e2b9ad83aa8aaad1808df75c479edee0` i PR #16: Ubuntu Swift-kernekontrol run 40558766100 **bestået**; macOS native-run 40558766103 **fejlet som workflow**, men underliggende job `Test and compile actual repository source` var `cancelled` uden udførte trin/kompilerfejl. Præcis aflysningsårsag er ikke bekræftet (runner-kapacitet, plan/billing, concurrency eller anden GitHub-afbrydelse undersøges særskilt). Gentagne kø-/annulleringsforløb er ikke i sig selv Swift-fejl.
5. **Google Drive** indeholder allerede Scan3D-filer. Filen, brugeren selv downloader til sin iPhone, kan ikke fjerninstalleres gennem ChatGPT. Et Drive-link eller en signatur-løs ZIP er ikke en fungerende iPhone-installation.
6. **Fysisk LiDAR:** Ingen bekræftet første scanning med iPhone 14 Pro Max, kamera-/tilladelsestest, reelt dybdemål, gemt og genåbnet model eller printtest fra denne release.

## Rettelser foreslået i denne draft-PR

- Giv XcodeGen **eksplicitte** versions- og buildnumre, og sæt begge boolske Files-delingsnøgler i en genereret Info.plist.
- Udvid eksisterende `package_unsigned_ipa.py` så pakning **fejler lukket** når nøglerne mangler. Gem også versionsnumrene i det eksisterende SHA-256-manifest.
- Udvid packaging-enhedstests med positive, manglende og ugyldige værdier. Kontroller at en gammel version uden nøgler afvises efter samme regler.
- Tilføj **læsebeskyttet CI Doctor**: hent faktiske GitHub-run-/job-/artefakt-metadata, sammenhold alle resultater med samme 40-tegns SHA, skeln code failure fra annulleret job, kørsel i kø og ældre artefakter; producer `scan3d-ci-doctor.json` og `scan3d-ci-doctor.md` som GitHub Actions-artifact og oversigt.
- Autokør diagnosticering ved PR'er, på fuldførte native/portable-workflows og dagligt **først når workflowet eksisterer på default-branch**. Ingen automatisk ændring i `main`, ingen PR-merge, bruger-login, personlige Apple-hemmeligheder, køb, signering, publicering eller skjulte tests. Doctorens grønne job betyder kun, at *diagnosen blev lavet*, ikke at iOS eller LiDAR er godkendt.

## Prioriterede milepæle og målbare godkendelseskriterier

| Prioritet | Leverance | Automatisk kontrol | Fysisk/human gate |
|---|---|---|---|
| **P0** | Integritetskontrolleret, versionsmærket iPhone-IPA | App-version/build, iPhone ARM64, Files-delingsnøgler, SHA-256, originale kilde-SHA, ingen private signeringsnøgler | Egen Apple-konto / faktisk signering |
| **P0** | Grønt ægte iOS-build på seneste commit | Det originale required check `Test and compile actual repository source` på *præcis* SHA; simulator-UI, Debug, Release og device ARM64 | macOS-runner og iPhone-installation |
| **P0** | Fysisk LiDAR-rundtur | Enhedsmålinger logget lokalt (stabil AR-tracking, faktisk `smoothedSceneDepth` eller `sceneDepth`, gyldige confidence-data) | iPhone 14 Pro Max: kamera-tilladelse, mål 30–200 cm, pause/genoptag, genåbn projekt |
| **P1** | 2-trins brugerflade: **Scan** / **Redigér 3D** | Automatisk UI/screenshot ved portrait, landscape og stor tekst; nul døde knapper | Fysisk ergonomi, tilgængelighed |
| **P1** | Automatisk capture med konservativ kvalitetskontrol | Fra ægte frames: tracking, dybde/confidence, sløring, lys, kamera-hastighed, overlap og nye vinkler; ingen automatiseret optagelse ved tvivl | Fysisk forskellige motiver og lysforhold |
| **P1** | Sikker offline-projektlagring i Filer | Atomisk filskrivning, originalfiler, manifesthash, afbrudt optagelse, lav lagerplads, backup og gendannelse; ingen cloud som standard | Gem/åbn fra Filer på telefon |
| **P2** | Geometri og 3D-print | Punkt-mesh tydeligt adskilt; OBJ/PLY bevares; STL kun ved manifolds- og lukket-overflade-test, ingen opdigtede flader | Sammenlign med fysiske mål og 3D-print |
| **P2** | Intelligent lokal efterbehandling | Rå sensor-kilde og kvalitetsbegrundelser logges; konservativ fusion og registrering, automatisk forslag om gen-scan ved huller, maskering kun hvor belyst af data | Reelle LiDAR-referenceobjekter |
| **P3** | Automatisk fejltriage | Run-ID, SHA, første fejlede trin, årsagsklasse og link til kilde; genkørsel højest én gang efter dokumenteret infrafejl og separat godkendt politik | Ingen tavs kodeomskrivning eller skjult auto-merge |

## Installation: iPhone først, Windows kun bag kulissen

1. Build **opdateret** usigneret iPhone-IPA med manifest og offentlig CI-kvittering for præcis head-commit. Godkend ikke en gammel IPA, selvom den kan hentes fra Drive.
2. Signér på en måde, der er forenelig med en ejerstyret Apple-konto. Windows/AltServer og AltStore Classic er en *mulig* testvej; Apple-kontoens oplysninger skal ikke sendes til GitHub/ChatGPT. Gratis sideload kræver normalt fornyelse efter syv dage; Wi-Fi/USB og PC-tilgængelighed kontrolleres reelt.
3. På fysisk iPhone: åbn app, giv eller afvis første kamera-tilladelse, afprøv gendannelse via Indstillinger, påvis en stabil ARKit-LiDAR-dybde, scan et lille ikke-blankt objekt, gem/åbn projekt igen, eksporter målte PLY- og eventuelle OBJ-data, kontroller filen i Filer.
4. Hvis telefonen ikke virker: lokal fejlrapport må **ikke** forveksle syntetiske simulatorframes eller browserpreview med ægte LiDAR.

## Automationssikkerhed

- På en PR må automatisering **læse/rapportere, teste og udgive artifacts i GitHub Actions**; skrivning til `main`, merge, firmware-opdatering, app-publicering, installation og Apple-kontosignering er udenfor automatisk tilladelse.
- GitHub API-diagnosen må ikke udlevere tokens, kopiere personlige scan-filer, bruge cloud til billeder eller ændre branches.
- Uden godkendt macOS-build er der ingen ny installationsklar Scan3D-version. Ingen beregnet procent kan erstatte bevis på rigtig enhed.

## Dokumentation

- Apple: [sceneDepth](https://developer.apple.com/documentation/arkit/arconfiguration/framesemantics-swift.struct/scenedepth), [smoothedSceneDepth](https://developer.apple.com/documentation/arkit/arconfiguration/framesemantics-swift.struct/smoothedscenedepth), [CFBundleVersion](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion), [UIFileSharingEnabled](https://developer.apple.com/documentation/bundleresources/information-property-list/uifilesharingenabled).
- GitHub: [Workflow cancellation](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-cancellation), [Troubleshooting](https://docs.github.com/en/actions/how-tos/troubleshoot-workflows).
- AltStore: [Windows installation](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows), [syvdagesfornyelse](https://faq.altstore.io/altstore-classic/your-altstore).
