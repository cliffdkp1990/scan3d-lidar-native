# Gratis installation og løbende brug af Scan3D LiDAR

Undersøgt 27. oktober 2026. Brugeren oplyser iPhone Pro/Pro Max med LiDAR, iOS **27.0.1** og har nu kun sin iPhone ved sig. Brugeren har bekræftet både fysisk placering i EU og EU-land på Apple-kontoen. Den primære vej er derfor **AltStore PAL → AltStore Classic 2.3.1 (70) → parring direkte på iOS 27** med en gratis Apple-konto. Ifølge AltStores aktuelle dokumentation kan denne kombination sættes op uden computer. Det er endnu ikke en fysisk installationstest. Windows-scriptet bevares som fallback. Apple-login, tofaktor, installationstilladelser og eventuel Developer Mode bekræftes af brugeren selv. Ingen merge, deployment, udgivelse eller betaling er foretaget.

## Hvorfor LiDAR endnu ikke virker på telefonen

Den native Scan3D-kode bruger allerede ARKit `smoothedSceneDepth` og, hvor understøttet, `meshWithClassification`. Safari kan importere en eksporteret model, men starter ikke denne native ARKit-session. Et browserskift installerer ikke scanneren. Der mangler verificeret signering, installation og opstart af den native app på brugerens telefon.

Den kontrollerede IPA er en rigtig **arm64 iPhone Release**, men den er usigneret og kan ikke installeres direkte. Pakken er fra commit `de48b2cfd542ac341f9b168b5603e1e83fdb5786`; native kildetræ-hash `6fd3cbc88ff76e23ff38af3f16f6ead74b7c1d27` er identisk med den native kode i browser-reviewet `570c84cffd895e326fabd8f3956f277ec798d5e0`. IPA SHA-256: `5ebf4424203356d3ea672df1603ba60db0f26bb788e7038e986af164b9da799d`. Alle seks pakkefiler er hashkontrolleret. Projektet konfigurerer ingen betalte app-capabilities eller ekstra app-extensions; dette er ikke i sig selv en vellykket gratis signeringstest.

## Fornyelse efter syv dage

Apple angiver syv dages udløb for gratis Personal Team-profiler og højst tre installerede apps pr. enhed: [Apple Developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account/). LiDAR-sensoren udløber ikke. Classic installeret med udviklersignering bruger selv en sådan app-plads; PAL-installationen må ikke ukritisk tælles som samme installationstype. Rettidig fornyelse kan holde Scan3D brugbar efter den første uge; det er ikke permanent signering, og uafbrudt drift kan ikke garanteres.

**Rettelse til den tidligere vejledning:** Førstegangsparring med PC er ikke et universelt krav på iOS 27. AltStores [officielle opslag fra 14. september](https://bsky.app/profile/altstore.io/post/3mviuyldlt22q) beskriver parring på telefonen og en helt computerfri start for PAL-brugere. FAQ-billedteksten “Pair with a PC” beskriver ikke hele den aktuelle vej. De [aktuelle versionsnoter](https://faq.altstore.io/release-notes/altstore) og [Classic-kataloget](https://cdn.altstore.io/file/altstore/apps.json) viser stabil 2.3.1, som retter blandt andet -80045, tofaktor og baggrundsfornyelse. Det officielle PAL-katalog på `https://marketplace.altstore.io` viste ved kontrollen marketingversion **2.3.1 (70)**, dateret 23. oktober; det interne versionsfelt `2.3.2` er ikke det synlige versionsnavn. Ingen Patreon-begrænsning var angivet for den stabile post.

PAL bruges til at installere den notariserede **Classic**. Vores egen usignerede Scan3D installeres derefter gennem Classic. Direkte udgivelse af Scan3D på PAL ville kræve betalt udviklerkonto/notarisering og er hverken nødvendig eller udført her. Se [AltStores officielle sammenligning](https://developer.altstore.io/).

## Start på iPhone uden Windows

1. Åbn [altstore.io/download](https://altstore.io/download) i Safari. Tryk Download, følg iPhones besked om at tillade markedspladsen fra **AltStore LLC**, gå tilbage og vælg Download samt installation af markedspladsen. Den aktuelle side angiver iOS 18+ og kræver berettiget region; brugerens oplyste iOS 27.0.1 og bekræftede EU-forhold opfylder de beskrevne indledende betingelser. Apples [regionskrav](https://support.apple.com/118110) skal fortsat håndhæves af telefonen; region ændres ikke af vores kode.
2. Åbn [AltStores officielle Classic-listing](https://api.altstore.io/source/marketplace.altstore.io?app=com.rileytestut.AltStore), vælg Add Source i PAL og installer den stabile Classic. Der er ikke behov for en Patreon-beta til det beskrevne forløb.
3. I Classic: Indstillinger → **Set up Remote AltServer**. Følg den aktuelle guide til parring på enheden og LocalDevVPN. Brug Wi-Fi; brugeren læser serveroplysninger og godkender selv VPN-/parringstilladelser. En ekstern server kan indgå; dette er ikke beskrevet som udelukkende lokal signering.
4. Hent den allerede kontrollerede Scan3D-artefakt direkte til iPhone. ZIP'en indeholder den usignerede IPA og dens manifest. Gem i Filer, pak ZIP'en ud, og importer `Scan3D-unsigned.ipa` i Classic. ZIP'en skal ikke ændres til `.ipa`; det er filen inde i ZIP'en, der importeres. Login og eventuelle sikkerhedsvalg gennemføres af brugeren.
5. Åbn native Scan3D, tillad kameraet og gennemfør de fysiske kontroller nedenfor. Opsæt først planlagt fornyelse efter en vellykket manuel fornyelse med bekræftet ny udløbsdato.

Den aktuelle kontrollerede pakke kan hentes fra GitHub-run [40451480580](https://github.com/cliffdkp1990/scan3d-lidar-native/actions/runs/40451480580), artifact-ID **12711022768**. Browserdownload kan kræve GitHub-login. Den forbundne GitHub-downloadfunktion kan i stedet give et direkte, kortlivet HTTPS-downloadlink i chatten uden ny deployment eller ændret adgang; linket udstedes først, når brugeren er klar. Gem ikke downloadlinkets signerede query i GitHub. ZIP SHA-256: `7eeae5784bb304db79ede3b4ea26d5c3712c10e6e4ab17c2d31f63ceb37b8c2c`. Artifactet er tidsbegrænset hos GitHub; ikke et permanent distributionslink. Den ældre private preview-pakke fra commit `8134b3f` er en anden version og udskiftes ikke uden tilladelse.

## Windows-fallback og fysisk accept

En ny [iPhone-genvejskladde og genbrugelig bygger](../integration/iphone/README_DA.md) samler LocalDevVPN, fem sekunders ventetid og Classics fornyelseshandling, hvorefter Classic åbnes til faktisk resultatkontrol. Byggeren signerer, uploader, installerer og planlægger intet. Importerbar signering, hensigtenes kompatibilitet og rigtig fornyelse af Scan3D skal stadig bekræftes; en usigneret kladde er ikke en færdig iPhone-genvej.

1. Kontrollér original IPA og installer med scriptet nedenfor. Bevar eksisterende scanninger og den originale usignerede pakke.
2. Færdiggør AltServer og Apple-komponenterne på Windows. Den officielle [Windows-vejledning](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows) forventer desktop-iTunes og desktop-iCloud fra Apple. Denne computer har Store-iTunes; udskiftning er derfor ikke automatiseret. Biblioteker, Apple-programmer og brugerdata skal bevares. Manglende standard-DLL'er er et kontrolpunkt, ikke bevis for at alle alternative installationer fejler.
3. Tilslut iPhone med datakabel, lås op og godkend computeren på telefonen. Windows' enhedsregistrering beviser hverken parring eller LiDAR.
4. Installer AltStore Classic gennem AltServer. Brugeren indtaster selv Apple-konto og tofaktor i den officielle app samt bekræfter profilens tillid og Developer Mode. Ingen adgangskoder skrives i chat, script, GitHub eller rapporter.
5. Importér den kontrollerede Scan3D-IPA i Classic. Bevar Apple-konto og installeret appidentitet ved fornyelse. Signeringsværktøjet kan tilføje team-suffiks til bundle-ID; kontrollér identiteten, før en eksisterende installation opdateres. Slet ikke appen som rutinefejlretning.
6. Åbn native Scan3D og kontrollér faktisk LiDAR-dybde/mesh, foto, video uden lyd, gem/genåbn og PLY/OBJ-eksport. Importér projektkopien i Safari. Sensorbevis skal komme fra den fysiske telefon.
7. Kør først manuel **Refresh All**, og kontrollér at udløbsdatoen flyttes. Opsæt derefter Remote AltServer via Classics egen vejledning. Brugeren installerer/aktiverer LocalDevVPN og læser den valgte servers oplysninger. En ekstern server kan indgå; forløbet beskrives ikke som udelukkende lokalt. Ingen fremmede VPN-konfigurationer kopieres ind.
8. Efter vellykket manuel fornyelse kan Classics tilgængelige Refresh All-handling indgå i en personlig iPhone-automatisering. Test låst og ulåst telefon og faktisk ny udløbsdato efter planlagt kørsel. Et færdigt Shortcut er ikke tilstrækkeligt bevis. Brug efter den oprindelige udløbsdato kræver også en senere kontrol; det er endnu ikke afprøvet.

Ved Remote-fejl beholdes app/data; lokal AltServer med USB er fallback. Slet ikke Apple ADI-filer, profiler eller scanninger, og slå ikke Windows-beskyttelse fra.

## Én genbrugelig Windows-startfil

Standardkørslen kontrollerer pakken og lokale forudsætninger samt skriver en statusfil. Den henter, installerer og starter intet:

```powershell
./integration/windows/Start-Scan3D-Free.ps1 -PackageDirectory <mappe-med-IPA-og-SCAN3D_PACKAGE.json>
```

Tilvalg:

- `-Prepare`: hent den officielle, fastlåste AltServer 1.8.00-installer.
- `-InstallAltServer`: anmod om normal Windows-installation. Brugeren kan skulle godkende Windows-prompten.
- `-OpenAltServer`: åbn appen efter kontrol af pakke, standardbiblioteker og Windows-telefonregistrering.
- `-WhatIf`: vis handlingerne uden download/installation/start.

Scriptet fjerner ingen Apple-programmer og ændrer ikke execution policy, firewall, VPN, certifikater eller Developer Mode. Login udføres af brugeren. En ny fremtidig IPA kræver et opdateret kontrolleret hashgrundlag; en vilkårlig IPA accepteres ikke. Den eksisterende GitHub Flow-hentning kan fortsat hente nye CI-pakker; ingen ny manuel ZIP-proces er nødvendig.

Installer: `https://cdn.altstore.io/file/altstore/altserver-windows/1_8.msi`. SHA-256 `944186a28493b628a7702c514155140d530dfadc31f4279033ae576f1403cd5f` matcher [Microsofts WinGet-manifest](https://github.com/microsoft/winget-pkgs/blob/master/manifests/r/RileyTestut/AltServer/1.8.00/RileyTestut.AltServer.installer.yaml). MSI-egenskaberne angiver AltServer 1.8.00 / Riley Testut. MSI og programfilen er **ikke Authenticode-signeret**; kontrollen bygger på officiel HTTPS-kilde og krydstjekket hash. Windows-advarsler godkendes af brugeren.

`integration/windows/Test-Scan3D-Free.ps1` tester hashafvisning og beredskab uden installation, netværk eller Apple-login. Rapporten indeholder ikke Apple-konto, UDID eller parfil. Adgangsfejl bliver ukendt, ikke bestået. Standard-DLL-kontrollen beviser hverken korrekt arkitektur eller fungerende signering. Scriptet kontrollerer ikke alternative brugerdefinerede Apple-biblioteksmapper.

## iOS 27.0.1 og forumkontrol

De aktuelle kataloger viser Classic 2.3.1; en minimumsversion og fejlrettelsesnote beviser ikke problemfri drift på **27.0.1**. [Reddit-erfaringer fra 23. oktober](https://www.reddit.com/r/AltStore/comments/1xd7eeq/seems_altstore_is_fixed_now/) og [en anden fejltråd](https://www.reddit.com/r/AltStore/comments/1xd8efw/error_installing_altstore/) er blandede. Officiel [issue #1803](https://github.com/altstoreio/AltStore/issues/1803) omhandler Remote-parring på iOS 27. PAL-katalogets aktuelle stabile post nævner også rettelse af `BGTaskSchedulerErrorDomain 3`; dette er en udvikleroplysning og ikke vores telefonbevis. Ingen af disse observationer erstatter telefonprøven. Ukendte patches, eksperimentel randomisering af appidentitet, deaktiveret beskyttelse og sletning af loginfiler er ikke anvendt.

SideStore bevares som undersøgelsesspor, ikke som en parallelt installeret løsning. [Releases](https://github.com/SideStore/SideStore/releases), [#1584](https://github.com/SideStore/SideStore/issues/1584) og [#1623](https://github.com/SideStore/SideStore/issues/1623) beskriver login-/fornyelsesproblemer. Record3D er fortsat valgfrit og har et særskilt Wi-Fi-tilkøb; det er ikke nødvendigt for den valgte gratis native vej.

## Faktisk verifikation

Windows 11 Home 64-bit og Store-iTunes er fundet. Original IPA og AltServer-installer er hashkontrolleret. Normal Windows-installation blev forsøgt, men ikke bekræftet gennemført. Da brugeren kun havde iPhone ved sig, blev kun dette arbejdes ventende `msiexec`-klient afbrudt efter kontrol af proces-ID, programsti og præcis MSI-kommandolinje. Apple-programmer og øvrige installerprocesser er bevaret. PAL-/Classic-links, aktuelle katalogposter og iOS 27-dokumentation er læst. Den direkte artefaktdownload er kontrolleret mod SHA-256 og filmanifest; iPhones Filer-udpakning, Classic-import, native opstart, fysisk LiDAR, fornyelse og brug efter syv dage er endnu ikke verificeret. Ingen betaling, OS-sikkerhedsændring, merge eller deployment er udført.
