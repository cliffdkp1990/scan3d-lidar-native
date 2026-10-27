# Chrome og lokal iPhone-dybde

Seneste valg er **Safari på iPhone**. Webvisningen er skiftet tilbage til Safari-tekst; Chrome er fortsat en testet modtager på Windows. Safari/WebKit-test er ikke en fysisk Safari-installation og giver ikke i sig selv ARKit-adgang.

Separat reviewgren oven på PR #10 ved de48b2cfd542ac341f9b168b5603e1e83fdb5786. Native Swift/ARKit, eksisterende PR'er, workflows og main-beskyttelse bevares. Ingen merge, deployment, signering eller køb.

## På iPhone først

Chrome bevarer fotos, lokale projekter, projektimport, modelvisning og eksport. Google beskriver Chrome til iOS som WebKit-baseret: https://developer.chrome.com/docs/web-platform/blink . Websiden får ikke ARKit sceneDepth ved at skifte browser. Den eksisterende native Scan3D-app bruger ARKit på understøttet hardware og kan dele .scan3d.json med modellen til webversionen. Native installation kræver separat signering; dette arbejde installerer eller signerer ikke appen. LiDAR-telefonen er oplyst af brugeren, ikke fysisk kontrolleret. Se IPHONE_CONTINUOUS_USE_DA.md om løbende brug og fornyelse.

## Record3D til Chrome på Windows

1. Record3D skal være installeret med det nødvendige Wi-Fi-tilkøb. Appen køber eller installerer intet. Krav: https://record3d.app/ .
2. På Windows: Node.js 22+ og Google Chrome. Kør web/safari-mvp/Start-Chrome-LiDAR.ps1, eller `node tools/serve.mjs --record3d` fra den mappe og åbn http://127.0.0.1:4173/ i Chrome. Serveren binder kun loopback; telefonen skal ikke åbne denne adresse.
3. Hold Record3D åben på iPhone, start Wi-Fi-streaming, og brug samme private Wi-Fi på begge enheder. Kontroller Record3D Wi-Fi max. depth = 3 m og HTTP-port = 80. Disse leverandørindstillinger kan ændres; de må ikke gættes. Skriv telefonappens private IPv4-adresse i Chrome på Windows og bekræft indstillingerne. Samme iPhone kan ikke holde begge apps i forgrunden samtidig. Netværksisolering kan forhindre forbindelsen; appen ændrer ingen sikkerhedsindstillinger.
4. Tryk Forbind Record3D, derefter Gem dybdeudsnit. Hvert udsnit bliver et nyt projekt med ASCII XYZ PLY. Den gamle model erstattes ikke. En ikke-gemt kladde skal gemmes, før der skiftes projekt.
5. Stop stream eller skjul fanen for at lukke modtagelsen. Ingen automatisk genforbindelse. Sikkerhedskopi og original model kan eksporteres som før.

## Hvad data betyder

Record3D kan levere TrueDepth- eller LiDAR-baseret RGBD. Wi-Fi-protokollen dokumenterer ikke en pålidelig sensorattestation. Derfor hedder strømmen altid RGBD / sensor ikke bekræftet, selv på en LiDAR-telefon. Sensorvalget i leverandørens app er ikke verificeret her.

Venstre halvdel er HSV-dybde med z = 3 × hue meter ved bekræftet 3 m-indstilling; højre halvdel er farve. Der kræves eksplicit K og originalSize. Ugyldige/ujævne dybder filtreres, og højst 20.000 XYZ-punkter omtrent 0,1–2,8 m gemmes. Koordinater er kamerarelative med negativ z foran kameraet. Kompression og ændret kamerakalibrering kan forringe resultatet. Ingen fusion af flere billeder, world-pose-rekonstruktion, farvet mesh, vandtæt objektmodel eller kalibreret måling. Et dybdeudsnit er ikke en færdig objekt-scanning.

Kilder kontrolleret 2026-10-27:

- https://github.com/marek-simonik/record3d-simple-wifi-streaming-demo ved c824d97594ead37665aad28821b319f891a49c66. /getOffer, /metadata og /answer; ingen ekstern JavaScript importeres.
- https://github.com/marek-simonik/record3d-wifi-streaming-and-rgbd-mp4-3d-video-demo ved a463841774d3507771860d65c2dc29d254eb647a. HSV/metadata; MIT-licens bevares i third-party/Record3D-MIT.txt.
- https://apps.apple.com/us/app/record3d-3d-videos/id1477716895 . Versionshistorikken dokumenterer justerbar Wi-Fi-dybde og port.
- https://developer.apple.com/documentation/arkit/arconfiguration/framesemantics-swift.struct/scenedepth .

## Sikkerhedsgrænse

Relæ er slået fra uden --record3d. Det kræver loopback-host, præcis same-origin POST, application/json og tilfældig token pr. proces. Kun kanonisk privat IPv4; aldrig URL, DNS, brugerdefineret port eller offentligt mål. Kun tre faste HTTP-endpoints på port 80 med tids-/størrelsesgrænser. Ingen redirects, STUN/TURN, mikrofon eller cloud. SDP filtreres til valgt privat host-kandidat og én aktiv videostrøm. WebRTC-video går direkte mellem enhederne; HTTP-relæ håndterer kun signalering. Telefonens signalering er almindelig HTTP på dit private netværk.

CSP connect-src ændres fra none til self for relæet; ingen eksterne domæner. Lagerformat, ID'er, filgrænser og strenge OBJ/PLY-parsere er uændrede. Ingen runtime-afhængigheder.

## Testdesign og faktiske grænser

`node --test tests/*.test.mjs` tester eksisterende adfærd plus kalibrering, dybde, punktgrænser, integritet, IP/SDP, CSRF/token og langsomme/store HTTP-requests. `pnpm exec playwright test --config playwright.chrome.config.mjs` kører eksisterende forløb i Google Chrome og nye syntetiske RGBD-forløb ved 390×844, 844×390 og 1480×910. De nye forløb kører også i WebKit. Separat Chrome-test sender syntetiske pixels gennem rigtig loopback-WebRTC uden kamera/STUN. UI-testenes syntetiske signalering er ikke en rigtig Record3D-forbindelse.

Windows WebKit har ikke canvas.captureStream. UI-testene bruger dér en tydeligt mærket syntetisk H.264-video og en track-adapter i testfixturet; videodekodning, pixelaflæsning, konvertering, lager og eksport er ægte browserkode. På Chrome og WebKit med canvas.captureStream bruges syntetiske canvas-tracks. Adapteren findes kun i QA-fixturet, ikke i produktmodulet. synthetic-rgbd.mp4 er vores egen 640×240-testvideo uden kamera, lyd eller telefondata.

Eksisterende WebKit-regression og Swift→web-kontrakt bevares. Hver CI-kvittering registrerer checkout og PR-head. Denne tekst beskriver testdesignet; kun Actions og deres kvitteringer dokumenterer beståede commits. Fysisk iPhone/Chrome/Safari, LiDAR, Record3D-tilkøb, lokalnet, kamera og Gem i Filer er uverificeret uden særskilt evidens. Intet er deployet.
