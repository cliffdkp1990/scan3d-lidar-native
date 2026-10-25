# Kamera og LiDAR — Camera Studio

Mål: en tydeligere optageoplevelse, bedre faktiske fotos og mere stabil målt LiDAR-geometri. Dette er reviewkode. En grønt kompileret app eller en Simulator med testmotiv dokumenterer ikke kvaliteten af et fysisk iPhone-kamera.

## Implementeret

- Kameraskærmen bruger et roligt kameraareal, en projiceret søger til det låste AR-punkt, konkrete instruktioner, tre kvalitetsindikatorer og tre dækningsrækker. Antal fotovinkler er ikke en overfladekvalitetsscore. AnyLayout bevarer den samme ARView ved layoutskift. Motion-blur, depth-of-field og ekstra kameragrain deaktiveres i RealityKit-renderingen; de ændrer ikke sensorens optik.
- Autofokus er aktiveret. ARKit vælger den anbefalede højopløsningskonfiguration, når den findes. Et separat højopløsningsfoto bestilles med captureHighResolutionFrame; der er stadig kun én AR-kamerasession. Den faktiske opløsning, kilde, orientering, intrinsics og billedkontrol registreres pr. foto. Der loves ikke et bestemt megapixelantal eller 4K-video.
- Nye fotos afventer, at kameraets autofokus ikke længere er under justering. Manglende kameraadgang og afbrydelser får konkrete fejlbeskeder. Kameraindstillinger åbnes kun med brugerens tryk. Sporingsfejl skelner mellem bevægelse, få billeddetaljer, opstart og relokalisering.
- Et request-token låser projekt, generation og fotoposition. Selve den leverede AR-frame efterkontrolleres. En tidsgrænse håndterer udeblevne callbacks, og dubletter eller gamle callbacks registreres ikke som en ny optagelse. Højopløsningsfejl slår automatisk foto fra med forklaring; der er ingen skjult fallback mærket som højopløsning.
- JPEG gemmes med kvalitet 0,95, sRGB og fysisk orienterede pixels. LiDAR-sampling, sammenlægning, billedkontrol og encoding kører på den serielle filkø. Der er højst én fotooptagelse i behandling. Originaler og atomisk manifestlogik bevares ved genfoto og skrivefejl.
- En central luminansgrid på 96 × 96 bruges til lys- og detaljevejledning cirka fire gange pr. sekund. Den præcise frame genkontrolleres ved lagring. Videorange og full-range YUV normaliseres korrekt, og padded rows håndteres. Få detaljer alene afviser ikke en mat genstand: det er ikke bevis for uskarpt fokus. Meget mørke/lyse billeder og ukendt kontrol afviser automatisk foto. Grænserne er heuristik og skal kalibreres fysisk.
- Stabilitet måler nu både translation og drejning, inklusive roll via kameraets op-retning. En frisk billedkontrol og en støttet dybdepatch indgår i optagebeslutningen. Høj termisk tilstand standser nye fotogodkendelser.
- LiDAR kræver medium/høj ARKit-confidence med korrekte dimensioner/strides. En robust central patch afviser dybdespring. Isolerede dybdespidser afvises med nabostøtte. Der samples hvert andet dybdepixel og samles i 8 mm voxler med begrænset løbende middel. Dette giver tættere visningspunkter, ikke 8 mm målenøjagtighed. Punktbudgettet er fortsat begrænset.
- Det låste punkt projiceres med ARCamera og den faktiske viewport/orientering. Punkter bag kameraet skjules; punkter udenfor billedet får en kantanvisning. Låsningen bruger dybde og intrinsics, men er fortsat et overfladepunkt og ingen semantisk objektisolering.
- Ekstra motivklassifikation er et tilvalg. Den kører ikke som standard på bekostning af kamera og billedkontrol. Videoens eksisterende sikre 1280 px/15 fps-profil, uden lyd, er bevaret.

## Faktisk validering og resterende arbejde

CI skal køre eksisterende tests, nye luminans-/CoreVideo-/dybde-/bevægelses-/token-tests og kompilere appen. Native UI-tests starter appen med tydeligt mærket syntetisk testmotiv. Testprojektet bruger en isoleret midlertidig mappe; det har ingen adgang til brugerens normale projektmappe. Fixture-koden er DEBUG-betinget og aktiveres kun af testmiljøet.

UI-forløbene omfatter portræt, landskab, stor tekst med scroll til optageknappen, mørk-billede-vejledning, tilladelses-/afbrydelsesbeskeder, projektbibliotek og den rigtige RealityKit-resultatviewer med syntetisk geometri, drej, zoom, knib, træk og reset. Kontrollerne undersøger også vandrette skærmgrænser og den faktiske landskabsrotation. Den første visuelle gennemgang fandt ældre iPhone-letterboxing samt afskæring ved landskab/stor tekst; launch-screen, understøttede retninger, breddebegrænsning og fleksibel header er rettet. Resultater og screenshots skal inspiceres, før de påstås bestået. En Simulator aktiverer ikke ægte LiDAR.

En separat iOS-test sender rigtige syntetiske CoreVideo-buffere gennem CameraImageQuality og CoreImage/ImageIO. Alle fire grænsefladeretninger kontrolleres for JPEG-afkodning, billedmål, sRGB og allerede orienterede pixels. Det dokumenterer encoding-pathen, ikke sensorens fysiske retning. CI bygger både Debug og Release; testmotivets aktivering er ikke tilgængelig i Release. Se den præcise revisions workflow-resultat for faktisk udfald.

Manglende fysisk evidens: højopløsningscallback/latens og samtidig video, roterede fotos, kamera/LiDAR-kalibrering, skarphed/eksponering på forskellige genstande, dybdefiltre ved kanter og tynde overflader, batteri/varme, termiske callbacks og framerate. Der er ingen signeret installation eller fysisk Safari-/iPhone-test påstået. Fotogrammetri, objektisolering og detaljeret video/foto-til-model er separate udestående projektdele.

## Primære API-kilder

- https://developer.apple.com/documentation/arkit/arsession/capturehighresolutionframe(completion:)
- https://developer.apple.com/documentation/arkit/arconfiguration/recommendedvideoformatforhighresolutionframecapturing
- https://developer.apple.com/documentation/arkit/ardepthdata/confidencemap
- https://developer.apple.com/documentation/xcode/specifying-your-apps-launch-screen
