# Scan3D Studio — naturlige flader · native integration

**Status:** separat kode-PR til review. Ikke godkendt fysisk LiDAR-test, signeret IPA eller automatisk merge.

## Ny funktion
- Over den **eksisterende ARView** vælges `Naturlig`, `Flader` og `Trådnet`. Naturlig er starttilstand.
- `Flader` tegner let mintfarvet skygning oven på **faktiske, projicerede ARKit-scene-mesh-trekanter** i nærheden af det låste mål. Skygningen varierer med orienteringen. Nabotrekanter fremhæves kun med en tynd kant, hvis forskellen i fladenormal er stor (ca. 35°). Dette skelner store vinkelbrud fra hele trådnettet.
- `Trådnet` er ARViews eksisterende diagnostiske `showSceneUnderstanding`, ikke et nyt overfladefilter.
- Den samme ARSession, kamera, automatisk foto, video, det eksisterende mesh og PLY/OBJ-eksport bevares. Skærmoverlejringen lagres **ikke** i originalfiler.
- Overflader vises kun, når genstanden er låst, tracking er stabil, og ARKit faktisk rapporterer scene-mesh. Manglende mesh viser blot den oprindelige kameravisning og en forklaring. Ingen syntetiske overflader i en fysisk optagelse.

## Begrænsninger
- ARKit-scene-mesh kan indeholde baggrundsflader, fejl, manglende hjørner og utilstrækkelig opløsning. Det er **ikke** kalibreret dybde, automatisk objektisolering eller en lukket/printklar STL.
- En 2D skærmoverlejring uden særskilt dybde-occlusion kan ved visse vinkler vise geometri foran forkerte kameradele. På dette stadium begrænses visningen til en radius om det låste mål og geometrien inden for kameravinduet. Fysisk test skal vurdere fejlfarvning.
- Præsentationen bruger højst ca. 480 udfyldte trekanter og 240 markante kanter fra højst 2600 analyserede mesh-trekanter ved ca. 3 Hz. Begrænset for termisk belastning; ved serious/critical viser appen kun naturligt kamera.
- UI-fixture i Simulator er syntetisk; fotovinkler er **ikke** procent overfladedækning.
- Stop/genstart af scanner følger eksisterende sikre regler og starter evt. et nyt AR-koordinatsystem. Ikke nogen uverificeret `Stop og gem`-knap i denne ændring.

## Validering
1. Native CI skal kompilere den faktiske SwiftUI/ARKit-kilde på macOS; ImageTests kontrollerer overfladetilstand og kanttærskel.
2. Simulator: Naturlig/Flader/Trådnet skal kunne vælges med VoiceOver og stor tekst. Ingen falske LiDAR-data i fixture.
3. iPhone 14 Pro Max: scan en kasse, en skrå rampe og en metalbeslag med ca. 90-graders kant; kontroller tynde markeringer, ghosting, tracking, overlay alignment i portræt og landskab.
4. Verificér samme eksporterede PLY/OBJ og originalsæt ved skift af visning; test pause, afbrydelse, varme og videostop.
5. Ingen merge til beskyttet `main` før obligatoriske checks og fysisk kvalitetsvurdering.

Designkilde: PR #31, `docs/SCAN3D_STUDIO_NATURLIGE_FLADER_V06_DA.md` på designbranchen.
