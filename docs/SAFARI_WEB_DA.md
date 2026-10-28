# Scan3D Safari Studio · separat reviewversion

Denne webapp ligger i `web/safari-mvp/`. Den bygger videre på foto-/projektprototypen fra PR #8 uden at ændre den eksisterende branch eller PR. Native Swift/ARKit, native tests og det eksisterende iOS-workflow er uændrede. Den nye reviewgren er stacked på `feature/safari-scan3d-mvp` ved `8325821e01d8dca9306fbeacd23f553b3390a35a`, som bygger på PR #1 ved `8134b3f2f31b61f259e66e44ade459d773546fa0`.

## Det kan webversionen

- Start et brugergodkendt livekamera, tag JPEG-fotos og vælg billeder fra Filer/Fotos. Ingen lyd eller mikrofon. Kameraet stoppes ved Stop, projektskift, modelvisning, biblioteksåbning, `visibilitychange` til skjult og `pagehide`. En sent godkendt gammel kameraanmodning kan ikke genåbne kameraet.
- Gem/genåbn projekter i IndexedDB med binære ArrayBuffers, SHA-256 og atomiske transaktioner. Blob-filer genskabes ved læsning; tidligere vellykkede Blob-poster kan stadig læses. Al binær serialisering afsluttes før transaktionsstart. Revisionskontrol afviser en forældet fanes overskrivning. Mislykket skrivning bevarer en tydeligt mærket kladde i hukommelsen; den kan eksporteres. Lagerfejl må aldrig kaldes en vellykket lagring.
- Vis fotos og forstør dem. Uploads kontrolleres for filtype/signatur og faktisk afkodning; appen gemmer JPEG-kopier på højst 1600 pixels uden opskalering. Eksterne originalfiler ændres ikke. HEIC understøttes ikke af denne import; livekamera og JPEG/PNG/WebP er alternativer.
- Importér native Scan3D ASCII XYZ PLY eller trekantet OBJ uden tekstur/materialer. Readerens regler og normalisering er portet fra `GeometryPreview.swift`; visningsnormalisering ændrer ikke de originale koordinater eller eksportbytes. WebGL-visningen har drej, zoom, nulstil, fingertræk og knib. PLY er punkter, ikke en rekonstrueret overflade. En ny model i et projekt, der allerede har en model, gemmes i en ny projektkopi. Den gamle model bevares.
- Prøv den samme syntetiske vaseprofil som `StudioFixtures.swift`. Demoen opretter sit eget mærkede projekt; den er ikke en scanning af kameraets billeder. Kontrolmønstrene fra den tidligere separate browserdemo genbruges, men der er ingen afhængighed af den private Sites-preview, en ChatGPT-widget eller en CDN.
- Klargør og hent en samlet JSON-sikkerhedskopi med faktiske filer og hashes. Deling via filunderstøttet Web Share tilbydes kun, når browseren annoncerer understøttelse. Klargøring og den brugerudløste deling er separate trin, så asynkront arbejde ikke bruger iOS' delingsgesture op. Download/deling betyder ikke, at appen kan bekræfte en fysisk fil i Filer.
- Importér backup som en ny projektkopi med nye ID'er. Tidligere version 1-eksporter kan læses. Den første prototypes `scan3d-safari-mvp-v1`-lager kan importeres eksplicit; en atomisk markør hindrer gentagen import af samme indhold. Det gamle lager slettes eller omskrives ikke.

## Grænser og sikkerhed

Safari-webversionen får **ingen ægte LiDAR eller ARKit sceneDepth**. Foto/video-til-3D-rekonstruktion, tekstur, vilkårlig GLB/STL-import, kalibrerede mål og 3D-printreparation er ikke implementeret her. Native-appens eksisterende videofunktion bevares.

Webkameraet kan nu optage korte videoer uden lyd, når browseren understøtter MediaRecorder. Der anmodes ikke om en mikrofon. Browserens eget understøttede MP4-format foretrækkes; ellers vælges WebM eller dens standardformat. Maksimum er tre klip pr. projekt, 30 sekunder og 8 MiB pr. klip; projektets samlede 24 MiB-grænse gælder stadig. Tidsgrænsen er et foreground-timerstop, ikke en garanti ved OS-suspendering. Optageren venter på den sidste dataavailable før lagring. Skjult fane, pagehide eller afbrudt kamerasporet afslutter optagelsen, men en iOS-tvangslukning kan miste et igangværende klip.

Vælg video importerer lokalt MP4/WebM, som faktisk kan afkodes af browseren. Videoerne vises med standardafspilning, gemmes binært med SHA-256 og kan hentes enkeltvis. Manglende optage-API deaktiverer kun livevideo. Codec-, størrelses- eller lagerfejl viser en forklaring. Efter et færdigt klip findes en særskilt download, hvis projektlagring mislykkes; tidligere gemte data bevares. Importerede klip beholder eventuel eksisterende lyd; appens egne optagelser er uden lyd.

Eksisterende lokale version 2-poster og projektarkiver version 1/2 læses fortsat. Backup uden video forbliver version 2, og native-broen er uændret. Backup med video er version 3: en gammel app afviser den i stedet for at tabe klip. Tidsmetadata kontrolleres mod en endelig varighed fra browseren; WebM uden varighed i containeren bruger optagelsens medfølgende tidsmetadata, ikke en uafhængig opmåling.

Windows' Playwright-WebKit har her ingen MediaRecorder eller canvas.captureStream og afviser lokalt oprettede H.264-Blob-URL'er, selv om samme testvideo kan åbnes via HTTP. Derfor registreres optagelse/import-afspilning som sprunget over i den motor, mens den faktiske afvisning, bevarede filer og genfindingsdownload testes. Chrome tester faktisk kodning af syntetiske kamerastreams. Hverken denne Chrome-test eller Windows-WebKit er fysisk Safari/iPhone-godkendelse. Den native installation og Apple-tilladelser er uændrede.

Grænser: 30 fotos/projekt, 40 projekter, 12 MiB pr. fotoinput, 32 megapixel ved billedafkodning, 8 MiB pr. model, 200.000 modelpunkter, 60.000 trekanter, 24 MiB binære data/projekt og 36 MiB backup. PLY-visningen sampler højst 20.000 punkter; alle importerede kildepunkter bevares i originalfilen. Store/ugyldige filer afvises med en forklaring. Uden WebGL kan projekter og originalmodeller stadig gemmes/eksporteres; der vises en tydelig grafisk fejltilstand.

Data ligger i browserens oprindelse, ikke i en cloudkonto. Siden bruger ingen eksterne runtime-afhængigheder, uploads, telemetri, nøglefiler eller tredjeparts-API'er. CSP afviser eksterne forbindelser, scripts, frames, objekter og formularafsendelse. Importerede navne indsættes som tekst. OBJ-materialer, eksterne billed-URL'er, SVG-fotos, ukendte protokoller, ikke-endelige koordinater, ugyldige indeks og nularealflader afvises.

Safari kan rydde lager, og privat browsing garanterer ikke vedvarende data. Backup er derfor nødvendig. `beforeunload` er kun ekstra hjælp; den er ikke en garanti mod iOS' lukning af en fane. Ingen service worker/offline-installation er indført. Appen kræver en server; `file://` er ikke en understøttet startform. Livekamera kræver sikker kontekst, normalt HTTPS eller den lokale maskines loopback. `http://<Windows-IP>` er ikke et verificeret iPhone-kameraspor.

## Lokal start og gentagelige tests

Node 24 kræves til de registrerede tests. Selve appen har ingen installations- eller buildtrin:

```text
node web/safari-mvp/tools/serve.mjs
```

Åbn den udskrevne `http://127.0.0.1:4173/` på samme computer. Loopback er ikke et link, der kan åbnes på en anden telefon. Ingen deployment er autoriseret eller udført.

```text
cd web/safari-mvp
pnpm install --frozen-lockfile --ignore-scripts
pnpm test
pnpm exec playwright install --with-deps webkit
pnpm test:browser
```

Playwright er en versionslåst udviklingsafhængighed; låsefilen indeholder integritetshashes. Testserverens eksplicitte `--qa` aktiverer kun navngivne syntetiske fixtures. De er ikke produktfunktioner og må ikke bruges som fysisk kamerabevis.

Det separate `scan3d-safari.yml` tester den præcise PR-head med read-only repositoryrettigheder. Et isolationscheck afviser ændringer i Swift/ARKit, native tests, eksisterende iOS-/Doctor-workflows og fælles scripts. Det ændrer ikke main-beskyttelsen eller eksisterende checks. Nye tests erstatter ikke native godkendelser. Der er ingen merge-, deploy-, release-, signerings- eller installationshandlinger.

`TESTED_COMMIT.json` i den versionsnavngivne Actions-artifact registrerer faktisk checkout, PR-head, kørsels-ID/-forsøg og hvert testresultat. Kun en bestået kørsel for samme SHA tæller. Testlisten omfatter byte-/hash-roundtrip, korrupt backup, legacy-import, ugyldige modeller, fotogalleri, faktisk IndexedDB-genåbning, transaktionsabort, samtidige faner, kamerafejl, syntetisk kamerastream og modelbetjening ved 390 × 844, 844 × 390 og 1480 × 910. Der bruges ingen blinde retries.

WebKit på Linux med emuleret iPhone-størrelse er **ikke Safari-appen eller en fysisk iPhone**. Fysisk kamera, touch/pinch, orienteringsskift, baggrundslukning, privat Safari-lager og Del/Gem i Filer skal stadig afprøves på telefonen. Aktuelle faktisk testede commits og udfald fremgår af PR-beskrivelsen og Actions, ikke af denne liste over scenarier.

## Primærkilder undersøgt

- [WebKits lagerpolitik](https://webkit.org/blog/14403/updates-to-storage-policy/): kvoter, fejl og mulig rydning; der loves ikke permanent browserlager.
- [Apples Safari-videoanvisninger](https://developer.apple.com/documentation/webkit/delivering-video-content-for-safari): `muted` og `playsinline` til inline visning.
- [Playwrights browserdokumentation](https://playwright.dev/docs/browsers): WebKit og enhedsemulering; det er ikke fysisk Safari-certificering.
- [WebKits MediaRecorder-dokumentation](https://webkit.org/blog/11353/mediarecorder-api/): kapabilitetskontrol, MP4 og afsluttende videoevents. Telefonens aktuelle understøttelse skal stadig afprøves.
