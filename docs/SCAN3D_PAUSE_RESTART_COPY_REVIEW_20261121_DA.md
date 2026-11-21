# Scan3D Studio – pause og genstart af kameraet

Ændringen er begrænset til **ordlyd og en vejledning** i `CaptureStudioView.swift`. Den ændrer ikke `ScanEngine`, lagring, ARKit, eksport, signering eller camera/video-kodning.

## Hvorfor?

I `ScanEngine.stop()` sættes `needsNewCoordinateSpace = true`, og `start(using:)` kalder `resetMission()`. Derfor kan en pause ikke beskrives som problemfri fortsættelse i den samme 3D-mission. Fotos og 3D-punkter, der allerede er skrevet til biblioteket, forbliver bevaret.

## Nye iPhone-tekster

- **Pause kamera** mens ARKit-sessionen kører.
- **Genstart kamera** når den er standset.
- Ved genstart: **'Kameraet starter i et nyt 3D-koordinatsystem. Lås genstanden igen. Allerede gemte fotos og punktskyer bevares i Mine scanninger.'**
- Status: **KAMERA PÅ PAUSE** eller **KAMERA KRÆVER HANDLING** i stedet for at antyde, at scanningen stadig er i gang.

## Tests før godkendelse

- [ ] GitHub Actions native iOS Simulator build på præcis PR-head-SHA bestået.
- [ ] Simulator UI: kamera starter med LIVE; pause viser KAMERA PÅ PAUSE, Genstart kamera og forklaring.
- [ ] Tilladelsesfejl: KAMERA KRÆVER HANDLING og den eksisterende hjælpetekst vises.
- [ ] UI stor tekst/VoiceOver og landskab: teksten bliver synlig uden at dække vigtige knapper.
- [ ] Fysisk iPhone: scanning → foto gemt → pause → nyt mål → tidligere fotos stadig i Mine scanninger.
- [ ] Video efter pause: færdiggørelse kontrolleret uden datatab.

Ingen af de ovenstående tests er udført eller erklæret bestået alene på grund af dette commit. Review og CI skal verificeres. Ændringen er en selvstændig native UI-fix og ikke en implementation af hele designforslag #31.
