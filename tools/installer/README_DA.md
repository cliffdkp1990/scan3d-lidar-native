# Scan3D - én klik til installationsklargøring

**Version:** Scan3D LiDAR med indbygget "Test min LiDAR", iOS-build fra PR #23
(`3863502b6aa9929bbe6fb204e0c71ed05e1ef0bb`).

Dette er en **automatiseret klargøring til personlig installation**, ikke en App Store-udgivelse eller en signatur-omgåelse. Ægte iPhone-installation kræver fortsat brugerens egen Apple-konto, tilladelser og AltStore Classic.

## Så nemt som muligt på iPhone

1. Åbn [AltStore PAL](https://altstore.io/download) fra Safari. Installer derefter **AltStore Classic** gennem PAL.
2. I Classic: **Settings → Set up Remote AltServer**. På understøttet iOS 27 kan parring ifølge AltStore ske uden en PC; brug Wi-Fi og godkend selv parring, LocalDevVPN og eventuelle eksterne serverforbindelser. En VPN eller ekstern server kan have privatlivskonsekvenser; det er ikke automatisk eller skjult.
3. Download `Scan3D-unsigned.ipa` fra den kontrollerede testpakke og gem i iPhones **Filer**. I Classic: **My Apps → + → vælg IPA**.
4. Accepter selv Apple-login, 2FA, signering og iPhones eventuelle Developer Mode. Scan3D bevarer samme appidentitet; slet ikke en ældre installeret scanner for at opdatere.
5. Åbn Scan3D → **Test min LiDAR** → scan en genstand → gem og genåbn projektet.

**Begrænsning:** iOS Genveje, Safari, Google Drive eller Windows kan ikke springe Apples provisioning, første parring eller brugerens tilladelser over. En direkte `altstore-classic://install` med en privat Drive-URL er ikke verificeret; vi bruger derfor den understøttede filimport frem for at påstå et ubekræftet 1-kliks-sideload.

## Én klik med Windows som hjælper

Den komplette leverings-ZIP indeholder disse filer i **samme mappe**:

- `Start-Scan3D.cmd`: dobbeltklik. Starter kun det medfølgende PowerShell-script med procesafgrænset execution policy, ingen permanent Windows-ændring.
- `Start-Scan3D.ps1`: kontrollerer den faktiske IPA + alle SHA-256-filer og manifestets kilde-SHA; henter om nødvendigt **officiel AltServer 1.8.00** og kontrollerer leverandørens på forhånd fastlåste SHA-256 inden normal Windows-installation og UAC-godkendelse. Åbner AltServer og IPA-mappen.
- `Scan3D-unsigned.ipa`: en rigtig usigneret iPhone ARM64 Release, **ikke** signeret eller installeret.
- `SCAN3D_PACKAGE.json`: versionsnummer, build, faktisk SHA-256 og kildecommit.
- `Test-Scan3D.ps1` og denne vejledning.

Det er ikke et simpelt ubegrænset "run latest": Pakken accepterer **kun** PR #23 iOS-build på eksakt commit `3863502b...`, IPA SHA-256 `8c1987f7a3bae83742d95025c2c7ee219b711ab446a02948141871747e536fac` og de interne SHA-256-filer. Et udløbet/ændret artifact kan ikke lydløst erstattes af en anden version.

### Windows-start

1. Gem ZIP'en lokalt på Windows og pak den ud.
2. Dobbeltklik **Start-Scan3D.cmd**. Det er et eksplicit valg om at klargøre AltServer på computeren, inkl. mulig Windows-UAC. Programmet sletter ikke Apple-programmer, scanninger eller appdata.
3. Scriptet kontrollerer iTunes/iCloud-biblioteker og valgfrit tilsluttet iPhone, og åbner den officielle [AltStore Windows-vejledning](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows), hvis der mangler afhængigheder. Den installerer **ikke** automatisk iTunes/iCloud over din eksisterende opsætning.
4. Sidste handling på iPhone er fortsat **AltStore Classic → My Apps → + → Scan3D-unsigned.ipa**. Ved første installation skal du selv godkende konto og tilladelser.

Kun kontrol uden nogen installation:

```powershell
powershell.exe -NoProfile -File .\Start-Scan3D.ps1 -CheckOnly
```

Offlinetest uden installationssideeffekter:

```powershell
powershell.exe -NoProfile -File .\Test-Scan3D.ps1
```

## Automationsgrænser

- Henter eller ændrer ikke dine Apple-loginoplysninger, certifikater, iPhone-scanninger, kameraoptagelser, VPN-konfigurationer eller andre apps.
- Ingen app-deploy, signering, selvinstallerende iPhone-app, ændring af `main` eller merge i denne klargøringskode.
- Windows-scriptets `-InstallAltServer` er et **eksplicit valg**; i dobbeltklik-starteren er valget indbygget og synligt, og Windows kan kræve UAC.
- Status på Windows beviser **aldrig** at Scan3D er installeret, at LiDAR virker eller at udløbsdatoen er fornyet.
- Gratis Classic-installation udløber normalt efter syv dage; indbygget baggrundsfornyelse skal afprøves separat på din telefon.

### Kontrollerbare kilder

[AltStore Classic vs PAL](https://github.com/altstoreio/FAQ/blob/main/altstore-pal-v.-altstore-classic.md) ·
[Remote AltServer](https://github.com/altstoreio/FAQ/blob/main/altstore-classic/remote-altservers.md) ·
[Windows-installation](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows).

## Automatisk pakke efter hver ny godkendt native iOS-build

**Ny automatisering i denne PR:** `build_verified_package.py` kan modtage den faktiske
GitHub Actions-artifact med IPA og `SCAN3D_PACKAGE.json` fra et bestået, SHA-bundet
native-run. Byggeren kontrollerer kilde-SHA, faktisk IPA-hash, hvert arkivmedlems
SHA-256, det byggede `Info.plist`-versionsnummer, bundle-ID og platform, og opretter:

- `Scan3D_iPhone_verified_<kilde-SHA>.zip`: `Start-Scan3D.cmd`, Windows-sikkerhedsscript,
  IPA, manifest, dansk guide og kort iPhone-starttekst.
- `Scan3D_iPhone_verified_<kilde-SHA>.json`: verificeret kvittering for kilde, IPA-hash,
  arkiv-hash og de endnu ikke udførte Apple-/hardwaretest.

`.github/workflows/scan3d-auto-package-after-native.yml` skal på beskyttet
`main` for at kunne starte automatisk, når det originale native iOS-workflow er
**grønt** på samme aktuelle hovedcommit. Automatiseringen afviser gamle builds,
annullerede jobs og mismatch mellem SHA og hentet artifact. Den opretter kun et
tidsbegrænset **privat GitHub Actions-artifact**. Den deployer ikke offentligt,
lægger ikke appen på Google Drive, signerer ikke en Apple-app og installerer
ikke noget på telefonen uden brugerens handling.

PR #25 er en reviewændring: indtil den merges via normal beskyttet PR-proces,
er den kontinuerlige `workflow_run`-automatisering **ikke aktiv på main**.
Den hidtidige kontrollerede PR #23 IPA er en gennemtestet kildeversion, men
ikke et løfte om, at den er seneste kilde på `main`.
