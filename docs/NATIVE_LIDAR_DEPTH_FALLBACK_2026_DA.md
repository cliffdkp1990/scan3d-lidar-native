# Scan3D native LiDAR · robust dybde-fallback, 28. oktober 2026

## Hvorfor denne ændring er nødvendig

Apple ARKit tilbyder `ARFrame.smoothedSceneDepth` (udglattet over flere frames) og `sceneDepth` (diskrete aktuelle målinger). Begge indeholder en dybdemåling i meter og kan have et `confidenceMap`. Udglattet dybde kan eksistere, mens dens centrale dybde er ugyldig, ekstrem eller med utilstrækkelig confidence. Den hidtidige `smoothedSceneDepth ?? sceneDepth`-strategi valgte kun rå dybde, hvis det udglattede objekt var **helt fraværende**. Det kunne blokere et ellers brugbart motiv.

**Kilder**
- [Apple: smoothedSceneDepth](https://developer.apple.com/documentation/arkit/arframe/smoothedscenedepth)
- [Apple: sceneDepth](https://developer.apple.com/documentation/arkit/arconfiguration/framesemantics-swift.struct/scenedepth)
- [Apple: ARDepthData og confidenceMap](https://developer.apple.com/documentation/arkit/ardepthdata)
- [Apple: punktsky fra ARKit scene depth](https://developer.apple.com/documentation/arkit/displaying-a-point-cloud-using-scene-depth)
- [Apple: captureHighResolutionFrame er out-of-band](https://developer.apple.com/documentation/arkit/arsession/capturehighresolutionframe%28completion%3A%29)
- [Remote Sensing Letters, 2026: iPhone LiDAR model-og-afstandsafhængig unøjagtighed](https://www.tandfonline.com/doi/abs/10.1080/2150704X.2026.2720055)

## Implementeret i denne pull request

1. `LiDARDepthFallbackPolicy.swift` giver en deterministisk beslutning: smoothed valid → smoothed; smoothed invalid, raw valid → raw; begge invalid → ingen måling.
2. `DepthBufferSampler.swift` returnerer de **samme to parrede og validerede CoreVideo-buffere** (depth/confidence) og en 25-pixel center-estimate. Den kombinerer **aldrig** pixels fra forskellige kilder.
3. `CameraImageQuality.swift` vælger en kandidat fra én konkret ARFrame med den fælles CoreVideo-kontrol.
4. `LiDARGeometry.swift` benytter samme kilde til faktiske XYZ-punkter som mål-afstand og centrummåling. De eksisterende krav om finite meterværdier, tilstødende konsistente pixels, accepteret confidence, gyldig kamera-intrinsics og bounded point collector forbliver aktive.
5. `ScanEngine.swift` rapporterer den faktisk valgte kilde under `Test min LiDAR` og skriver `lidar_depth_source` til billedets private projektmetadata. Ingen rå punkter, fotos eller Apple-identiteter uploades.

## Tests

- `Tests/depth-source/main.swift`: 6 Foundation-only cases i Linux CI med ingen ARKit-simulator og ingen påstand om rigtig LiDAR.
- `Tests/quality/main.swift`: 10 regressionschecks med faktiske separate `CVPixelBuffer`-allokeringer, realistisk padded row-stride, gyldig/ugyldig depth og confidence samt kontrol af, at eksportpunkterne stammer fra samme validerede kilde.
- Aktuelle billeder, projektformat, LiDAR-punktbegrænsning, OBJ/PLY-eksport, automatisk fotos og aktive brugerdata ændres ikke.

## Acceptkriterier

- Portable tests grønne på **præcis PR-head SHA**.
- macOS CoreVideo-kvalitetstests, iOS Simulator UI, unsigned Release-to-device og native required check `Test and compile actual repository source` grønne på **samme SHA**.
- På iPhone 14 Pro Max med **ejerens** signering: scannér mat overflade 30–200 cm væk, test både rå fallback og stabil smoothed depth, gem et foto, genåbn projekt og eksporter PLY. Se både dybdekilde og måling i diagnostics og den private projektmetadata.
- Sammenhold fysisk målt referenceafstand med ARKit-rapportering og angiv afvigelsen. *Beståede softwaretests er ikke millimeternøjagtighed, en lukket mesh eller printbar STL.*
- Ingen merge, deployment, signering, adgangskodehandling eller installation i denne PR. Den eksisterende browser-webapp og andre PR'er berøres ikke.

## Kendt teknisk begrænsning

Denne rettelse løser ikke installationstilladelser på iPhone, og den kan ikke rette et annulleret macOS-runnerjob. Apple signering og fysisk LiDAR-afprøvning kræver fortsat brugerens enhed. Koden forbedrer selve dybdevalideringen og gør den testbar.
