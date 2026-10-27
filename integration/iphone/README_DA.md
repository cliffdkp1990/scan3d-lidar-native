# Scan3D: én genvej til fornyelse

`build_shortcut.py` laver den samme gennemgåelige, usignerede plist ved gentagelse uden ekstra Python-pakker. En ændret destinationsfil bevares og stopper bygningen. Byggeren uploader, signerer, installerer og planlægger intet. Den separate `sign_shortcut.py` kan efter udtrykkelig brugeraccept samle bygning, ekstern signering, download og kontrol i én kommando.

```text
python integration/iphone/build_shortcut.py --output <ny-eller-uændret-mappe>
python -m unittest discover -s integration/iphone -p "test_*.py" -v
```

## Hvad genvejen forsøger at gøre

1. LocalDevVPNs `ControlLocalDevVPNIntent` med standarden **enable**, ikke toggle. Forbindelsens adresser ændres ikke.
2. Vent fem sekunder. Ventetiden er ikke et bevis på en klar VPN-forbindelse.
3. AltStore Classics `RefreshAllIntent` (**Refresh All Apps**). Det omfatter alle apps administreret af Classic, ikke kun Scan3D. Der udføres ingen appopdatering, sletning eller ændring af Apple-konto.
4. Åbn Classic, så brugeren kan se det faktiske resultat og Scan3D's udløbsdato.

Ingen falsk succesbesked tilføjes. AltStore kan returnere uden installerede apps og kan fortsætte fornyelsen i forgrunden efter omkring 27 sekunder. En afsluttet genvej beviser derfor hverken en ny Scan3D-udløbsdato eller en installeret scanner. VPN slukkes ikke efter en fast timer, da fornyelsen kan fortsætte. Brugeren skal selv tage hensyn til andre VPN-forbindelser.

## Forudsætninger og første opsætning på iPhone

PAL/Classic skal allerede være installeret. Classics egen **Settings → Set up Remote AltServer**-guide skal være gennemført med parring, brugerens gratis Apple-konto og LocalDevVPN-tilladelse. Scan3D skal være importeret og installeret i Classic. Brug Wi-Fi; mobildata er ikke en bekræftet erstatning. En webside eller denne Windows-kode kan ikke godkende iPhones tilladelser eller installere en personlig automatisering.

De gennemgåede kilder er LocalDevVPNs aktuelle genvejshandling (App Store-versionen observeret som 1.3) og Classic 2.3.1 (70) via PAL. Match med de faktisk installerede versioner, genvejsimport og hensigtenes parameteropløsning er endnu ikke afprøvet på en fysisk iPhone. En manglende/ukendt handling er en fejl, ikke et godkendt resultat. Brug i så fald Classics egen **Add to Siri…** eller **Refresh All Apps** i Genveje og LocalDevVPNs egen **Enable VPN**-handling. Ingen tilfældig anden app vælges som erstatning.

## Fra kladde til importerbar genvej

En `.UNSIGNED.plist` er ikke en færdig iPhone-download. Apple kræver signering ved deling/import. Der leveres derfor ingen fil med `.shortcut`-endelse, før en signering faktisk er gennemført. På en Mac med den nødvendige iCloud-adgang kan Apples `shortcuts sign` bruges; en standard GitHub-runner er ikke dokumentation for sådan adgang. Ingen Apple-konto bruges af dette script.

En alternativ mulighed er Cherris officielle Playground og dennes dokumenterede HubSign-service. Den kræver særskilt brugeraccept af, at selve genvejsdefinitionen sendes til tjenesten. Kilden indeholder ingen Apple-oplysninger, IPA, Scan3D-projekter, enheds-ID eller private downloadlinks. Publicering som offentligt iCloud-link er ikke indbygget eller udført.

Brugeren godkendte 27. oktober 2026 specifikt overførsel af de fire handlinger til Cherri/HubSign. Første forsøg gennem Playground 2.3.0 blev **afvist ved indholdskontrol**: `rawAction` omsluttede AppIntentDescriptor i `WFDictionaryFieldValue`. Filen er ikke leveringsversionen. Byggeren producerer derfor ikke længere denne fejlbehæftede Cherri-kilde. Den korrekte plist sendes i stedet uændret til samme aktuelle `/sign`-grænseflade, som Playgrounds egen offentlige eksportkode bruger. Scriptet anvender en ny anonym session og sit eget klientnavn. Browserens login/cookies eller brugerens Apple-konto læses ikke. En ældre offentliggjort HubSign-adresse kunne ikke DNS-opløses; ingen klientidentitet blev efterlignet.

Efter godkendelse kan agenten køre hele forløbet med én kommando. `lzfse` er kun nødvendig til den signerede fils indholdskontrol og installeres separat fra det fastlåste `requirements-audit.txt`. Der tilføjes ingen app- eller npm-afhængighed:

```text
python -m pip install -r integration/iphone/requirements-audit.txt
python integration/iphone/sign_shortcut.py --output <leveringsmappe> --approved-service-upload
```

Uden flaget sendes intet. Scriptet henter den signerede beholder tilbage, kontrollerer dens faktiske fire handlinger og kræver et enkelt `Shortcut.wflow`-payload uden ekstra arkivfiler eller efterfølgende bytes. Ukendt format, omdirigering, forkert vært eller parameterændring stopper leveringen. En eksisterende lokal fil med matchende kvittering genbruges efter indholdskontrol uden ny upload; dette er ikke en ny kontrol af det hostede link. Hosted bytes kontrolleres særskilt før aflevering. Linket leveres fra Cherris lager uden ZIP, men tjenestens opbevaringstid er ikke garanteret. Fejl og udløb må ikke beskrives som et permanent link.

En rettet, signeret fil er faktisk hentet og dekomprimeret med match af alle fire handlinger. AEA-header og payload er kontrolleret lokalt. Apples kryptografiske signaturaccept og parameteropløsning skal stadig kontrolleres ved import på iPhone; ingen fysisk kørsel eller automatisk fornyelse er endnu bestået.

Ved kompilering læses den resulterende plist tilbage og kontrolleres:

```text
python integration/iphone/build_shortcut.py --validate-plist <kompileret-plist>
```

Kontrollen kræver præcis de fire handlinger og deres parametre og afviser fremmede handlinger, tilføjede netværkskald, ændrede URL'er og uventede importspørgsmål. Den erstatter ikke Apples importkontrol eller telefonprøven. En signeret beholders indhold og import må ikke beskrives som kontrolleret alene på grund af filendelse eller en signeringskvittering.

## Automatisk gentagelse efter en godkendt prøve

Kør først manuelt på en ulåst telefon med Wi-Fi. Kontrollér, at **Scan3D selv** findes under My Apps, kan åbnes, og at dens udløbsdato flyttes frem. Først derefter vælges på telefonen **Genveje → Automatisering → + → Oplader → Tilsluttes → Kør med det samme → Scan3D Forny**. Den personlige trigger skal oprettes/godkendes på iPhone; den kan ikke skjules i en delt genvej. Et alternativ er en daglig trigger på et tidspunkt, hvor telefonen er på Wi-Fi.

Kontrollér efterfølgende kørsel på låst og ulåst telefon samt brug efter den oprindelige udløbsdato. iOS kan begrænse baggrundskørsel, AltStore kan kræve forgrunden eller et nyt login, og en netværksfejl kan hindre fornyelse. Gratis signering er stadig syv dage pr. vellykket fornyelse. Der er endnu ingen fysisk fornyelse eller permanent drift at påstå.

## Kortere vej allerede før genvejen

Den understøttede URL `localdevvpn://enable?scheme=altstore-classic` anmoder LocalDevVPN om at starte og åbner Classic cirka ét sekund senere. Det er alene en overlevering mellem apps, ikke en parring, installation, automatisk fornyelse eller forbindelseskontrol. Nogle chatklienter blokerer app-links. Fallback er at åbne LocalDevVPN normalt, forbinde og derefter åbne Classic. De installerede versioner og telefonens faktiske adfærd er endnu ikke verificeret.

## Kilder og kontrolgrænser

- [LocalDevVPN: URL og callback](https://github.com/jkcoxson/LocalDevVPN/blob/af3fd697803ada4ac2b8d518358f5ab0a534844c/LocalDevVPN/LocalDevVPNApp.swift).
- [LocalDevVPN: App Intents og standard enable](https://github.com/jkcoxson/LocalDevVPN/blob/af3fd697803ada4ac2b8d518358f5ab0a534844c/LocalDevVPN/VPNShortcuts.swift).
- [Classic: fornyelse, fejlhåndtering og fortsættelse i forgrund](https://github.com/altstoreio/AltStore/blob/bbc10d6964185b75a46c6ddd7476ac08df095308/AltStore/Intents/App%20Intents/RefreshAllAppsIntent.swift).
- [Classic: de medfølgende appgenveje](https://github.com/altstoreio/AltStore/blob/bbc10d6964185b75a46c6ddd7476ac08df095308/AltStore/Intents/App%20Intents/AppShortcuts.swift).
- [AltStore: Background Refresh og Add to Siri](https://faq.altstore.io/altstore-classic/your-altstore).
- [Apple: deling og signering fra kommandolinjen](https://support.apple.com/guide/shortcuts-mac/apd455c82f02/mac).
- [Cherri: signering og ekstern tjeneste](https://cherrilang.org/compiler/signing.html).

Ti lokale regressionstests kontrollerer bygning, gentagelse, bevarelse af ændrede filer, godkendelseskrav, downloadmål, arkivindhold og afvisning af ændrede handlinger/parametre, herunder den faktisk fundne descriptor-fejl. De tester ingen native sensor, rigtig telefoninstallation, automatiseringstrigger eller fornyelse. Den eksterne signering og indholdskontrol af den faktiske leveringsfil registreres særskilt. Native Swift/ARKit, Safari-appen, deres eksisterende tests og tidligere PR'er ændres ikke af disse filer. Ingen merge eller app-deployment udføres.
