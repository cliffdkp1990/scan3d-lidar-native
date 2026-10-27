# Løbende brug af den native LiDAR-app

Undersøgt 2026-10-27. Brugeren oplyser iPhone Pro/Pro Max med LiDAR og iOS **27.0.1**. Dette er en installationsvurdering, ikke bevis for installation eller fysisk test. Der er ikke signeret, installeret eller købt noget. Ingen Apple-konto, VPN, firewall eller Developer Mode ændres af denne gren.

Syvdagesgrænsen gælder gratis Personal Team-signering, ikke LiDAR-sensoren. Apple beskriver udløb og geninstallation: https://developer.apple.com/help/account/basics/about-your-developer-account . En gratis app kan fortsætte efter dag syv, hvis dens signering fornyes i tide. Det er ikke permanent signering.

## Egen app: SideStore er en kandidat

SideStores officielle FAQ beskriver fornyelse på selve iPhone og computer ved førstegangsopsætning: https://docs.sidestore.io/docs/faq . Forudsætninger: Windows, USB ved opsætning, Apple-konto, understøttet iOS, Wi-Fi og LocalDevVPN. https://docs.sidestore.io/docs/installation/prerequisites og https://docs.sidestore.io/docs/installation/install .

Installation og den første manuelle fornyelse skal lykkes, før automatisk fornyelse af Scan3D vælges. iOS bestemmer baggrundskørsel; uafbrudt drift kan ikke garanteres. Bevar bundle-ID, Apple-konto og eksisterende appdata; slet ikke appen som rutinemæssig fejlfinding. Parring kan kræve Windows igen efter opdatering eller fejl. Parfiler og kontooplysninger må ikke placeres i GitHub eller webappens lager.

**Aktuel konkret begrænsning:** SideStores officielle releases markerer 0.6.4 og ældre med brudt login, mens 0.7.0-alpha og nightly er testversioner. Automatisk download/installation af en ukontrolleret version er derfor ikke implementeret. Se https://github.com/SideStore/SideStore/releases . På iOS 27 er der rapporter om en genvej, der kræver en allerede åben SideStore-proces (#1584), og endpointfejl specifikt på iOS 27.0.1 (#1623). Det er fejlrapporter, ikke bevis for at alle enheder fejler eller at nyere builds løser problemet. Et vellykket manuelt og efterfølgende fornyelsesforsøg på netop denne telefon mangler, før kandidaten kan kaldes fungerende.

- https://github.com/SideStore/SideStore/issues/1584
- https://github.com/SideStore/SideStore/issues/1623

Hvis SideStore senere vælges og installation særskilt godkendes, er den konkrete afprøvningsrækkefølge: sikkerhedskopi af Scan3D-data; kontrolleret signering med samme bundle-ID; manuel Refresh All med Wi-Fi og LocalDevVPN; åbn den native Scan3D-app og kontroller LiDAR samt gem/genåbn; sammenlign ny udløbsdato med den foregående; prøv derefter en personlig genvej, som åbner SideStore før Refresh All. Kontroller særskilt låst og ulåst telefon. Automatisering må først betegnes som fungerende, når udløbsdatoen faktisk flyttes ved planlagte kørsler. Et gennemført Shortcut er ikke i sig selv bevis for fornyet signering. Hvis fornyelsen fejler, skal appen melde det, frem for at love permanent adgang.

AltStore Classic understøtter også baggrundsfornyelse og Siri-genveje, men kræver tilgængelig AltServer ved fornyelse. https://faq.altstore.io/altstore-classic/your-altstore . Det er mindre egnet til ønsket om primært iPhone-brug.

## Uden egen ugentlig udviklersignering

En App Store-scanner som Record3D kan levere dybdedata til webappen. Det undgår Personal Team-udløb for scannerdelen. Record3D kræver særskilt Wi-Fi-tilkøb for live-modulet og en anden enhed som modtager. Det er en ekstern scanner, ikke en færdiginstalleret native Scan3D-app. Se CHROME_LIDAR_DA.md. Egen App Store-distribution er en separat beslutning med medlemskab, signering og review; intet af dette er godkendt eller udført her.

## Reddit som undersøgelsesspor

Brugerens ønske om Reddit er fulgt. Erfaringerne bruges som spor, ikke som verificeret kompatibilitet:

- https://www.reddit.com/r/AltStore/comments/1kesjfn/ beskriver SideStore som løbende fornyelse, ikke fjernelse af syvdagesgrænsen. Det er krydstjekket med SideStores FAQ.
- https://www.reddit.com/r/AltStore/comments/1x8b17x/ rapporterer Windows-fornyelse via lokal AltServer. Det beviser ikke baggrundskørsel på brugerens iPhone.
- https://www.reddit.com/r/SideStore/comments/1w4q5q4/ rapporterer LocalDevVPN-problemer. Faste IP-konfigurationer fra kommentarer kopieres ikke ukritisk; officielle forudsætninger og telefonens netværk skal kontrolleres.
- https://www.reddit.com/r/sideloadly/comments/1xd5vfq/ indeholder nylige loginfejl. Derfor loves ingen problemfri aktivering ud fra forumindlæg alene.
- https://www.reddit.com/r/SideStore/comments/1wzp6pa/ beskriver startproblemer på iOS 27.0.1; svarene er indbyrdes forskellige.
- https://www.reddit.com/r/SideStore/comments/1wjpdhm/ beskriver manuel fornyelse, der virker, mens genveje/låst telefon fejler. Dette er krydstjekket med issue #1584 ovenfor.

Næste nødvendige telefonbevis er start af den valgte native app, faktisk LiDAR-optagelse samt vellykket og efterfølgende fornyelse. Eksisterende begrænsning mod Apple-signering og udgivelse gælder fortsat; et installationsforslag skal godkendes særskilt, før det udføres.
