# Regression: 3D-gestus og tilgængelighed på native iPhone

Dato: 21. november 2026. [Første fejlede main-run 44888763044](https://github.com/cliffdkp1990/scan3d-lidar-native/actions/runs/44888763044), kilde `c36821fa96bf446a7d3a8f1f8cf4f572c19544f9`.

## Verificeret fejl
- UI-test `CaptureStudioUITests.testActualStoredGeometryRendererAndControls` fejlede på linje 186: `geometry-viewport`s tilgængelighedsværdi blev ikke opdateret efter hurtigt swipe.
- Den faktiske skærmoptagelse og `scan3d-viewer-trace.log` viser, at swipe **blev registreret**, og at **3D-objektet faktisk drejede**. Det er derfor en tilstands-/tilgængelighedsfejl, ikke bevis på manglende 3D-rendering.
- Testens krav om både ændret VoiceOver-værdi og ændret 3D-silhuet er ikke svækket.

## Rettelse
- Ved UIKit-gestus beregnes ny `GeometryCamera`, renderer opdateres straks, og `onCameraChange` skriver samme kamera i `StoredGeometryViewer`s SwiftUI-`@State`.
- `accessibilityValue(cameraAccessibilityValue)` afledes allerede fra denne state.
- Ingen ændringer i ARKit, fotos/video, PLY/OBJ, hashkontrol, filer eller eksport.

## Test-gates
- [ ] Grønt native iOS build og alle UI-tests på eksakt PR-head SHA.
- [ ] Hurtigt/langsomt swipe ændrer synlig model og tilgængelighedsværdi; zoom/pinch/reset fungerer stadig.
- [ ] Fysisk iPhone-test mangler og må ikke påstås gennemført.

Denne PR er en separat kladde. Det nyere [main-build 44890304556](https://github.com/cliffdkp1990/scan3d-lidar-native/actions/runs/44890304556) kørte ved oprettelsen og skal vurderes. Ingen merge eller installation ved oprettelse.
