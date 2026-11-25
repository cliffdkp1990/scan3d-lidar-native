# Scan3D – installation af beta

## Windows + iPhone
1. Udpak hele ZIP-pakken. Tilslut iPhone via USB.
2. Start `Start-Scan3D.cmd`. Den kontrollerer den SHA-bundne IPA og eksisterende AltServer, men installerer ikke nye programmer automatisk. Kun en eksisterende AltServer med gyldig Authenticode-signatur er kandidat til automatisk start; en signatur er ikke garanti for Smart App Control eller fungerende Apple-forbindelse.
3. Hvis lokal AltServer faktisk virker: importér IPA i AltStore Classic og godkend Apple-signering.
4. Efter installation: Test min LiDAR, scan, gem, genåbn og eksportér.

Hvis AltServer ikke virker, bevar IPA'en. Gentag ikke login eller installation i blinde. Windows Smart App Control kan blokere usignerede programmer. Slå ikke sikkerheden fra som del af denne vejledning.

## iPhone uden pc
Hvis Remote AltServer allerede er parret: Wi-Fi (ikke mobildata) og LocalDevVPN skal være aktive. Test forbindelsen før IPA-import. Ved forbindelsesfejl se [officiel vejledning](https://github.com/altstoreio/FAQ/blob/main/altstore-classic/remote-altservers.md). Ingen påstand om at tidligere parring virker.

## Officiel Apple-distribution
Hvis de lokale signeringsveje ikke fungerer, er TestFlight en separat, officiel distributionsvej, som kræver Apple Developer Program-medlemskab og korrekt Apple-signering. Gratis Xcode-installation kræver adgang til en Mac. Ingen betaling eller Apple-login håndteres af dette script.

## Kontrol
`Start-Scan3D.ps1 -CheckOnly` verificerer IPA og manifest uden installation. `-SkipOpen` gemmer en diagnostisk rapport uden at starte programmer. Den eksplicitte `-InstallAltServer` funktion er ikke standard i CMD-starteren; den kræver både korrekt hash og gyldig Authenticode på installationsfilen. En gyldig signatur garanterer ikke sikkerhedspolitikkens accept. Apple-konto, tillid til enhed og eventuel Developer Mode godkendes af brugeren. Gratis personlig signering har normalt syv dages gyldighed. Intet i pakken beviser en fysisk installation eller LiDAR-test.

## Version
Kilde: `3863502b6aa9929bbe6fb204e0c71ed05e1ef0bb`.
IPA SHA-256: `8c1987f7a3bae83742d95025c2c7ee219b711ab446a02948141871747e536fac`.
Se SCAN3D_PACKAGE.json for faktisk version. Originaler og scanninger slettes ikke.
