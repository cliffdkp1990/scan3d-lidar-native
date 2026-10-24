# Scan3D — appplan med automatisk foto, video og 3D-objekter

24. oktober 2026. Plan og prioriteret byggegrundlag. Udgangspunktet er brugerens genfundne **Scan3D LiDAR – Pro Max v2** til iPhone 14 Pro Max. DroneHub bevares som et separat projekt.

## Aktuel reviewimplementering

Kilden ligger nu direkte i scannerens repository via draft PR #1. Den næste ændring tilføjer automatisk foto efter godkendt vinkel samt `ProjectStore` og **Mine scanninger** med virkelige fotominiaturer, genåbning, SHA-256-kontrol og individuel fildeling. Genfoto bevarer tidligere optagelser. Punktsky gemmes sammen med hvert registreret foto. Manifestet opdateres først, når filerne er gemt og læst tilbage. Skrivefejl stopper automatisk foto; gemte projekter åbnes uden at genbruge AR-koordinater. Genoptagelse efter kamera-pause kræver nyt mål/projekt.

Det er en reviewimplementering, der skal gennem CI og fysisk test. Den nye automatiske fotokontrol måler stadig ikke skarphed/eksponering. Video, foto-til-model, egentlig 3D-resultatviewer, samlet projektbackup/import og signeret installation er endnu ikke implementeret. Den oprindelige materialepakke er bevaret som historisk grundlag; den aktuelle kilde og denne faste appplan opdateres gennem GitHub-værktøjet uden ny ZIP.

## Den oplevelse, der skal bygges

**Peg på genstanden → Start → gå roligt rundt → få dit 3D-objekt.** Appen vælger passende indstillinger, tager billeder automatisk, kan optage video, gemmer løbende, kontrollerer dækningen og behandler modellen. Du skal kunne gennemføre den almindelige scanning på iPhone uden ZIP, filmapper eller en computer. Du skal stadig bevæge telefonen og vælge, hvilken genstand du vil scanne.

Første skærm viser en stor **Ny scanning**-knap og visuelle kort med dine tidligere scanninger. På optageskærmen er kameraet centralt, med én kort instruktion, en dækningsring og Start/Pause/Stop. Resultatet viser din faktiske 3D-model med drej og zoom, kildefotos, video og **Del**. Avancerede valg ligger under Flere muligheder.

## Hvad der allerede findes

| Område | Verificeret grundlag | Hvad der mangler |
| --- | --- | --- |
| Native iPhone-app | SwiftUI, ARKit, RealityKit, kamera og LiDAR-kode | Signeret installation og fysisk test |
| Fotoguide | 36 positioner, frisk frame-kontrol, stabilitetskrav, genfoto og ny automatisk udløser i review | Fysisk test af automatisk optagelse, skarphed/eksponering og enklere samlet brugerflow |
| Gemte fotos | Nyt projektmanifest med hashes, bibliotek, genåbning og bevarede genfotos i review | Fysisk afprøvning, samlet projektbackup/import og gendannelse af AR-mission |
| 3D-geometri | Målt LiDAR-punktsky som PLY og ARKit-scenemesh som OBJ | Objektisolering, egentlig resultatvisning, kvalitetskontrol og mere detaljeret model |
| Video | Ingen videooptagelse fundet i den hentede native kilde | Optagepipeline, afspilning, lagring og video som rekonstruktionsinput |
| Rekonstruktion fra fotos | Ikke implementeret i den genfundne app | Object Capture-/fotogrammetriforløb |
| Bygning | Seneste GitHub-test og usignerede Simulator-build bestået | Signeret fysisk enhedsbuild/TestFlight |

Grundlag: GitHub main `37aad26b594eb79183afbe197ba5ad3f7e07d412`, den checksumkontrollerede rettede v2-ZIP og run `40053563785`. Pakkens gamle README-status er historisk; den aktuelle CI-kontrol er nyere. Et grønt Simulator-build dokumenterer ikke fysisk LiDAR-kvalitet.

## Foto, video og 3D i samme projekt

### Foto

Standardforløbet tager automatisk billeder, når dækning, sporingskvalitet, skarphed, afstand og stabilitet er tilstrækkelige. Den eksisterende kontrol af den faktiske frame ved optagelsen bevares. Appen undgår dubletter og fortæller kort, hvor du skal bevæge dig hen. En manuel fotoknap er tilgængelig. Genfoto erstatter den valgte position i resultatet, mens originalfilen bevares i projektets historik.

### Video

Appen skal både kunne optage en almindeligt afspillelig video og bruge en egnet video som input til et 3D-objekt. Første mål er en stabil, testet optageprofil frem for maksimal opløsning. Appen tilpasser kvalitet efter varme, lager og faktisk enhedsydelse; den må ikke love 4K samtidig med alle scanningsfunktioner uden måling.

I det eksisterende LiDAR-spor undersøges optagelse af ARKit-kameraframes med tidsstempler, mens udvalgte billeder og dybdedata indsamles. Kamerabillede og vejledningsgrafik gemmes adskilt. En anden kamerasession må ikke konkurrere med ARKit om kameraet. Lyd er slået fra som standard; mikrofon er et særskilt brugerønske, og tv-lyd bruges ikke som kommandoer.

Ved **Video → 3D** udvælger appen skarpe, forskellige frames med overlap og sender dem til fotogrammetriforløbet. En importeret almindelig video indeholder ikke nødvendigvis dybde, kamerastillinger eller målestok. En model fra sådan en video må derfor vise ukendt fysisk skala, indtil den er kalibreret. Dårligt materiale skal give en konkret anvisning til ny optagelse, ikke en opdigtet model.

### 3D-objekter

Der planlægges to tydelige kvalitetsniveauer: **Hurtig 3D** fra den eksisterende LiDAR-geometri og **Detaljeret 3D** fra fotos eller udvalgte videoframes. Begge skal ende i en reel, drejbar model. En resultatillustration eller et ikon tæller ikke som modelvisning.

Apple beskriver Object Capture som optagelse efterfulgt af en særskilt rekonstruktion med PhotogrammetrySession. Appen skal kontrollere understøttelsen på den aktuelle enhed og tilpasse billedmængden til frameworkets grænser. Apples automatiske optagelse skal afprøves som primær vej til detaljerede objekter. [Apple ObjectCaptureSession](https://developer.apple.com/documentation/realitykit/objectcapturesession)

Object Capture og den eksisterende ARSession behandles som alternative optagelsesforløb. Samtidig Object Capture, brugerdefineret videostream og egen LiDAR-session er en teknisk afprøvning, ikke en forudsætning vi kan antage opfyldt. Hvis SDK'et ikke giver den nødvendige videoadgang i detaljeret tilstand, håndterer appen fotooptagelse og video som separate optagelser i samme projekt. Det skal fremgå før optagelsen.

Første modelmål er lokal iPhone-rekonstruktion, automatisk baggrundsforslag og en beskåret forhåndsvisning. Brugeren kan justere udsnittet. Automatisk oprydning bevarer råmodellen og gemmer en ny revision. Huller, usikker skala og svag dækning vises. Generativ AI må ikke erstatte manglende målt geometri uden særskilt, tydelig mærkning.

## Automatisering, der sparer dig arbejde

| Du gør | Appen gør automatisk | Ved problemer |
| --- | --- | --- |
| Trykker Ny scanning | Opretter projekt-ID, lokal mappe og egnet optageprofil | Forklarer manglende understøttelse eller lager |
| Peger og bekræfter genstanden | Foreslår objektafgrænsning og afstand | Beder om én konkret justering |
| Trykker Start og går rundt | Tager egnede fotos, registrerer dækning og gemmer data | Holder automatisk igen ved dårlig tracking eller uskarphed |
| Vælger Video eller bruger standardprofilen | Optager, segmenterer og afslutter videofiler sikkert | Stopper kontrolleret ved varme eller lagergrænse |
| Når rundt om genstanden | Foreslår afslutning eller næste manglende side | Tillader et bevidst ufuldstændigt kladderesultat |
| Afslutter optagelsen | Vælger gode frames, kontrollerer materiale og starter 3D-behandling | Gemmer input og tilbyder ny optagelse eller nyt forsøg |
| Åbner appen igen | Viser projekter, thumbnails og gendannelige opgaver | Nye AR-sessioner blandes ikke ukritisk med gamle koordinater |
| Trykker Del | Klargør modellen eller hele projektet og åbner iOS-delingsarket | Bevarer filer, hvis deling afbrydes |

Appen må ikke automatisk slette originaler, starte betalt cloudbehandling eller uploade private optagelser. Den almindelige arbejdsgang er lokal. Eventuel senere cloudbehandling vælges konkret af brugeren med kendt destination og pris.

## Byggeetaper og målbar afslutning

### 1. Stabilt projekt og installerbar baseline

Kopiér den rettede kilde ind som rigtig versionsstyret kilde i scannerens eget repository i en reviewgren. Den nuværende CI henter appen fra en ekstern ZIP; behold hashkontrollen i overgangsfasen og sammenlign importen. Bevar den senest beståede revision, ret forældede statusdokumenter og lad CI kompilere den faktiske appkilde. Ingen ændring af DroneHub, Lovable eller GitHub Pages.

Indfør `ProjectStore` med projektmanifest, fotos, video, rå geometri, behandlede modeller og thumbnails. Gem atomisk og registrér fejl, før UI viser Gemt. Originalfiler og revisioner får stabile ID'er og hashes. Overlev afbrudt skrivning og genstart. AR-verdenskoordinater fra forskellige sessioner holdes adskilt; fortsættelse efter genstart kræver verificeret relokalisering eller særskilt registrering.

Færdig når: appen kan installeres på den fysiske iPhone 14 Pro Max; kamera og LiDAR fungerer; et projekt kan gemmes, genåbnes og eksporteres. Apple-signering og distributionsadgang er en nødvendig engangsopsætning, som ikke findes dokumenteret i materialet.

### 2. Automatisk foto og video

Byg `CaptureCoordinator`, `QualityGate` og `VideoRecorder`. En fælles tilstandsmaskine har klar, optager, pause, gemmer og fejl. Automatisk foto kræver både ny brugbar position og aktuel kvalitetskontrol; tidsinterval alene er utilstrækkeligt. Video finaliseres korrekt ved Stop, afbrydelse og lavt lager. Ufuldstændige segmenter mærkes og bevares.

Færdig når: brugeren kan gennemføre en guidet scanning uden at trykke for hvert foto; almindelig video kan optages og afspilles; fotos, video og metadata ligger i det rigtige projekt; genfoto, pause og afbrudt optagelse blander ikke data.

### 3. Rigtige 3D-objekter og resultatvisning

Tilføj `ReconstructionCoordinator` til LiDAR-mesh, fotogrammetri og kvalificeret frameudvælgelse fra video. Test de to optagelsesveje separat, før de samles i brugerflowet. Vis faktisk fremdrift fra frameworket og tydelig fejlstatus. Giv mulighed for at stoppe uden at miste input. Rekonstruktion genstartes fra bevarede data; genoptagelse fra et præcist checkpoint loves kun, hvis SDK'et understøtter det og det er testet.

Resultatvisningen viser modellen i RealityKit med drej, zoom, reset og baggrundsvalg. Bevar PLY/OBJ. Tilføj USDZ som første mål til iPhone-visning og deling; GLB og STL er efterfølgende eksportmål med særskilt konvertering og validering. En STL mister tekstur og garanterer ikke et lukket mesh. Vis skala og kvalitet pr. model, ikke én generel succesetiket.

Færdig når: mindst ét fysisk objekt kan gennemføres fra fotos til en genåbnet 3D-model, og et separat egnet videoforløb kan blive til en reel model. Modellerne kan åbnes i en uafhængig viewer. Samtidig findes fejlforløb for for lidt overlap, blanke/genemsigtige overflader, dårlig skala og afbrudt behandling.

### 4. Enkel iPhone-app og kontrolleret distribution

Saml flows i tre områder: **Scan**, **Mine objekter** og **Resultat**. Gør automatiske valg til standard, med manuel kontrol under Flere muligheder. Store knapper, Dynamic Type, VoiceOver, reduceret bevægelse, haptik og korte instruktioner skal testes på telefonen. Filnavne, thumbnails og delingspakker oprettes automatisk.

Automatisér test, Simulator-build og signeret TestFlight-levering efter korrekt Apple-opsætning. Beskyt signeringsnøgler i CI's godkendte credentiallager; de skal ikke med i kildekode eller denne samling. Brugeren gennemgår og tester på iPhone. Mac-bygning kan ske i baggrunden; en ZIP skal ikke være del af det daglige appflow.

## Flere funktioner, der er relevante at implementere

Disse funktioner udvider de fire byggeetaper ovenfor. De er forslag til implementering, ikke funktioner der allerede er testet i appen. Standardforløbet skal fortsat have få knapper; ekstra værktøjer ligger i det relevante projekt eller under Flere muligheder.

| Funktion | Hvad du får | Prioritet og teknisk grundlag |
| --- | --- | --- |
| Visuelt objektbibliotek | Kort med modelbillede, navn, dato, optagelsestype og status; søgning og sortering | Første version. Bygges oven på den nye lokale ProjectStore; biblioteket findes ikke i den genfundne app |
| Import af eksisterende optagelser | Vælg fotos eller video fra Fotos/Filer; appen opretter et projekt og undersøger materialet | Første version efter lagring. Læsbarhed, rotation, filstørrelse, antal billeder og manglende skala valideres |
| Automatisk fravalg af dubletter og dårlige frames | Færre gentagelser, kortere behandling og en enkel besked om, hvilke optagelser der mangler | Første version. Hash bruges til identiske filer; visuel lighed, bevægelse og skarphed skal testes særskilt |
| Automatisk forslag til objektafgrænsning | Appen foreslår selve genstanden; du kan rette udsnittet med fingeren | Første version som forslag. Vision-koden har allerede et diagnostisk forgrundsområde; kobling til stabil 3D-beskæring kræver nyt arbejde |
| Dækningskort med næste bedste vinkel | Appen peger på den side, der mangler, frem for blot at tælle fotos | Første version ud fra den eksisterende 36-positioners guide. Detaljeret overfladedækning kræver egentlig geometrisk beregning |
| Måleværktøj og kalibrering | Markér to punkter på modellen og se en afstand; ret skala med et kendt fysisk mål | Efter den første reelle modelviewer. Vis enhed, skalakilde og at målet er vejledende; video uden kalibrering har ikke automatisk rigtig størrelse |
| Oprydning med før/efter | Forslag til at fjerne løse fragmenter, beskære bord/baggrund og reducere antallet af trekanter | Næste version. En ny modelrevision gemmes; rådata beholdes, og oprydning kan fortrydes |
| Kontrol før 3D-print | Vis åbne kanter, ugyldig geometri og usikker skala før STL-eksport | Næste version. Beslægtede kontroller findes i DroneHub-sporet; native kode skal implementeres og valideres. Automatisk hul-lukning er en senere prøve, som kan ændre formen |
| Få eksportvalg | Del på iPhone, send til 3D-program eller forbered til print; appen vælger passende format | USDZ og eksisterende PLY/OBJ først. GLB/STL kræver særskilt eksportimplementering. Tekstur og enheder kontrolleres efter konvertering |
| Automatisk coverbillede og modelvideo | Hver scanning får et miniaturebillede; lav en kort video af modellen, der drejer rundt | Coverbillede i første version. Roterende præsentationsvideo senere; den mærkes som modelvisning og holdes adskilt fra den optagede kameravideo |
| Se modellen i omgivelserne | Placér det genfundne objekt i AR og se det fra forskellige sider | Næste version med en understøttet USDZ-model. Visning i fysisk størrelse kræver kendt eller kalibreret skala |
| Enkel backup og gendannelse | Eksportér hele projektet med fotos, video, model og manifest, og indlæs det igen | Første version. Brug iOS-delingsarket; en valgt Filer/iCloud-placering er en brugerhandling, ikke en automatisk offentlig upload |
| Ressourcestyring | Appen tilpasser optagelsen, gemmer før den løber tør og forklarer pauser | Første version. Reagér på diskplads, termisk tilstand og afbrydelser; råoptagelser må ikke slettes for at frigøre plads |
| Genbehandling uden ny scanning | Vælg et eksisterende projekt og lav en ny model med de bevarede optagelser | Efter rekonstruktionsforløbet. Gem parametre og resultat som ny revision, så den tidligere model bevares |

**Første samlede leverance:** bibliotek og robust lagring, automatisk foto, videooptagelse, én gennemført foto-/video-til-model-vej, faktisk modelviewer og enkel deling. Måleværktøj, omfattende meshrensning, AR-præsentation og printforberedelse må ikke blokere, at det grundlæggende scanningsforløb bliver brugbart.

### Kvalitet og automatisering skal følge telefonens muligheder

Apples aktuelle dokumentation angiver `.reduced` som det understøttede detaljeniveau til lokal iOS-fotogrammetri. Planens Detaljeret 3D betyder derfor en fotobaseret model i telefonens understøttede kvalitet, ikke et løfte om desktopniveau på iPhone. En eventuel højere kvalitetsbehandling på Mac er et senere tilvalg og kræver særskilt adgang; den almindelige app skal stadig kunne bruges på telefonen. [Apple detail levels](https://developer.apple.com/documentation/realitykit/photogrammetrysession/request/detail)

Vision kan foreslå en forgrundsmaske i billedet. Det identificerer ikke automatisk alle sider af et 3D-objekt og er ikke i sig selv en færdig metode til at fjerne bord og baggrund fra modellen. Derfor bekræftes forslaget visuelt, og fejl kan rettes. Brug den API-variant, der passer til den valgte minimumsversion af iOS. [Apple foreground mask](https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest?changes=_2)

Appen skal heller ikke love ubegrænset rekonstruktion med låst skærm. Gem input og jobstatus, håndter iOS-afbrydelser og forklar, når behandlingen kræver appen åben. Automatisk sammenlægning af flere scanninger sættes til en senere teknisk prøve: sessionerne har forskellige koordinater og skal registreres korrekt mod hinanden først.

### Sådan godkendes de ekstra funktioner

Biblioteket skal kunne åbne det rigtige projekt efter genstart. Import skal håndtere både gyldige og beskadigede optagelser uden at overskrive et andet projekt. En beskæringsfejl skal kunne fortrydes. En måling skal skifte korrekt ved enhedsskift og ændret kalibrering. En eksportpakke skal kunne indlæses igen med samme optagelser og modelhashes. Oprydning må kun ændre den nye revision. Den roterende modelvideo skal være afspillelig og adskilt fra kameravideoen. AR og alle kvalitetsvalg verificeres på den fysiske iPhone.

## Test, der afgør om appen er færdig

- Enhedstest: automatisk foto uden dubletter, ny frame ved optagelsen, korrekt genfoto, projekters adskillelse, import/eksport, koordinater, enheder og fejl ved filskrivning.
- Simulator: navigation, biblioteksvisning, gendannelse og fejlskærme med tydeligt mærkede testdata. Ingen påstand om simuleret LiDAR som fysisk bevis.
- Fysisk iPhone 14 Pro Max: kameraadgang, foto, video, orientering, varme, lager, indgående opkald, app i baggrunden, pause/genoptag og genstart.
- Rekonstruktion: matte teksturerede referenceobjekter, vanskelige overflader og kendte mål. Registrér fejl og måleafvigelse; fastlæg kvalitetsgrænser efter de første fysiske målinger frem for at opfinde millimeterpræcision.
- Leverance: reel model kan drejes i appen, gemmes, genåbnes, deles til Filer og åbnes uafhængigt. Video er afspillelig efter kontrolleret afbrydelse, og fotos er intakte.

## Prioritet og afhængigheder

Først sikres installation, lagring og fysisk baseline. Derefter færdiggøres automatisk foto/video, så 3D-behandlingen har reelle input. Sidst samles modelkvalitet, enkel visning og distribution. Det er en rækkefølge af leverancer, ikke et verificeret tidsestimat. Ukendte forhold er Apple-signering, fysisk LiDAR-kvalitet, samtidig video/framework-adgang og lokal rekonstruktionsydelse. Hver afklares med en konkret prøve, før det afhængige arbejde kaldes færdigt.

## Referencer og sporbarhed

- Kode: `01_Native_aktuel/Scan3DLiDAR/Sources/` i materialepakken. `ScanEngine.swift` indeholder foto- og LiDAR-forløbet; `ContentView.swift` har UI og det nuværende resultatark. Der findes endnu ingen rigtig modelviewer i resultatarket.
- CI: [GitHub run 40053563785](https://github.com/cliffdkp1990/scan3d-lidar-native/actions/runs/40053563785).
- [Apple ObjectCaptureSession](https://developer.apple.com/documentation/realitykit/objectcapturesession): automatisk optagelse, enhedsunderstøttelse og særskilt rekonstruktionsfase.
- [Apple ARFrame timestamp](https://developer.apple.com/documentation/arkit/arframe/timestamp): sammenhæng mellem kameraets frames og optagetid. Pipeline og videoydelse er forslag, som skal implementeres og måles.
- Nye brugerkrav i denne samtale: saml eksisterende materiale; udarbejd en appplan; både fotos og video; skabe 3D-objekter; mest mulig automatisering; iPhone som den primære arbejdsflade.
