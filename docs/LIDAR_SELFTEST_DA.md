# Scan3D LiDAR-selvtest · fysisk iPhone 14 Pro Max

**28. oktober 2026.** Dette er en indbygget, lokal diagnose i den native SwiftUI/ARKit-app. Den ændrer ikke scanningernes filer, gemte projekter, mesh, video eller eksisterende automatisering. Intet uploades automatisk.

## Brug på iPhone

1. Installér en **Apple-signeret** Scan3D-build fra denne eller nyere præcist identificerede kildecommit. En usigneret IPA fra GitHub/Drive kan ikke åbnes som app direkte. Appens seneste grønne macOS- og portable-tests skal gælde præcis denne SHA.
2. Start appen på iPhone 14 Pro Max, tillad kameraet, peg imod et mat objekt ca. 0,3–2 meter væk, og vent på stabil sporing og dybde. Undgå genskin, ensfarvede flader og mørke.
3. Tryk **Test min LiDAR** under kameraets BILLEDE/LIDAR/SPORING-indikatorer. Den tager et tidsstemplet, **kun i hukommelsen**, øjebliksbillede af ARKits aktuelle sensorstatus. Ved videooptagelse eller igangværende fotogemning er knappen låst, så testen ikke afbryder en aktiv fil.
4. Se den automatiske diagnose. **ARKit modtager målt LiDAR-dybde** betyder, at en *frisk faktisk ARKit-frame* (seneste callback højst tre sekunder tidligere) er aktiv, kameraadgang er givet, en reel dybdemåling og tilhørende confidence-map findes, og tracking er normal. Det beviser ikke objektets 3D-nøjagtighed, en komplet overflade eller et godkendt print.
5. Hvis et led mangler, viser skærmen første konkrete årsag (kameraadgang, LiDAR-kapacitet, ingen frisk frame, ingen depth-map, confidence, ustabil sporing eller usikker centerafstand). Prøv bedre lys, langsommere bevægelse og et objekt med synlig overflade.
6. Tryk eventuelt **Del kun diagnoseteksten**. Der deles *kun status, målemetadata og antal fotos/punkter*, ikke billeder, enheds-id, GPS, rå-frames, punktkoordinater, projektstier, Apple-konto eller scannerfiler. **Deling er valgfri og kræver et aktivt tryk.**
7. Scan derefter en fysisk genstand, gem den, genåbn projektet fra **Mine scanninger**, og eksporter virkelig PLY/OBJ. Kontroller først derefter en fysisk referenceafstand og hullerne i modellen.

## Falske positive og kendte grænser

- DEBUG-fixture i iOS Simulator er altid mærket `TESTMOTIV: Ingen fysisk LiDAR-test`, selv om syntetiske kameramålinger ser grønne ud. Den må ikke tælles som rigtig sensorafprøvning.
- Diagnosticeringsstatus efter **Pause** er ikke et bevis for, at kameraet stadig kører. Der tælles kun ny modtaget ARSession-delegateframe, ikke en gammel cached `currentFrame`.
- Fraværende `smoothedSceneDepth` kan falde tilbage til `sceneDepth`. Diagnostics angiver den faktisk leverede kilde.
- Den viste 3D-dybde er baseret på scannerens allerede implementerede confidence-/nabofilter omkring søgerens center. Ingen millimeternøjagtighed eller STL-printbarhed påstås.
- Rapporten gemmes ikke automatisk og oprettes ikke i baggrunden. Nye skærmbilleder, login og installation håndteres ikke af ChatGPT.
- Når selvtesten vises, suspenderes automatisk capture. Den må ikke åbnes under video/fotogemning.
- Tester kun en sensorstatus **på et bestemt tidspunkt**; separat fysisk sporings-/afstandstest skal stadig godkendes.

## Kode og regressionstest

- `Sources/SensorDiagnostic.swift`: Foundation-only ren beslutningslogik og redigerbar, lokal tekstkvittering.
- `Sources/ScanEngine.swift`: ARKits `session.currentFrame`, `smoothedSceneDepth`/fallback `sceneDepth`, confidence, centerestimate, sporingsstatus og faktisk callbackstid. Måler ikke ved simulatorsyntese.
- `Sources/CaptureStudioView.swift`, `Sources/ContentView.swift`: iPhone-knap, lokal statusvisning og eksplicit SwiftUI ShareLink.
- `Tests/sensor-diagnostic/main.swift`: portable Linux-tests af frisk/forældet frame, tilladelse, depth, tracking, confidence, stale og fixture. `.github/workflows/scan3d-swift-portable.yml` kører dem på præcis PR-head.
- `UITests/CaptureStudioUITests.swift`: synlig UI-test i simulator kræver syntetisk mærkning, aldrig falsk fysisk LiDAR-godkendelse.
- **Fysisk sensorprøve mangler, indtil brugeren selv gennemfører den på den installerede app.** Grøn simulator/Swift-kontrol erstatter ikke det.

## Godkendelsesporte

1. Portable Swift-CI grøn på eksakt commit SHA.
2. Required macOS-check `Test and compile actual repository source` grøn på samme SHA, med iOS Simulator og iPhone Release-kode.
3. Ny hashkontrolleret usigneret IPA produceret af denne SHA; signering med ejerens egen Apple-konto.
4. Fysisk selvtest på iPhone 14 Pro Max: ikke-syntetisk grøn status, mål-/foto-/projektlagring og eksport af reel geometri.
5. Ingen merge, deployment, publicering eller ændring af eksisterende Scan3D-/DroneHub-datamateriale i denne PR.

**Separat scope:** De aktive web/Safari PR #21 og #22 forbliver uændrede og er ikke hardwarebevis.
