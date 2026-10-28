# Optagevejledning til rum og genstande

To originale SVG-illustrationer og tilhørende knapper hjælper brugeren i gang. Første valg opretter et projekt med kameraet slukket. I et eksisterende projekt ændres kun vejledningen; navn, fotos, videoer og model bevares. Først efter brugertryk på Start kamera anmodes der om kameraadgang. Valgene låses under optagelse og andre igangværende handlinger.

Korte vejledninger til rum og genstande kan foldes ud. Optællingen viser faktiske aktiver og siger tydeligt, når der ikke er en model. Der beregnes ingen kvalitetskarakter eller påstået 3D-rekonstruktion fra billedantal. Webappen får ingen ARKit-LiDAR.

Vejledningsvalg gemmes separat i browseren med højst 40 projekt-ID'er. Dårlige lagerdata ignoreres, og lagerfejl giver en synlig besked og en fungerende midlertidig vejledning. Projektformat, native import, foto/video og backupversioner er uændrede. Valget indgår ikke i projektbackuppen. Importerede kopier får en ny, uvalgt vejledning.

Fire Node-tests dækker datagrænser, ukendte valg, beskadiget lager og sandfærdige tællere. To browserforløb dækker oprettelse uden kameraanmodning, fokusering, skift med bevarede fotos, reload, 200 % tekst, uændret v2-backup og en eksporterbar kladde ved afvist projekt-/præferencelager. Eksisterende regressionstests bevares. Chrome-workflowets præcise forventede antal stiger fra 102 til 108 for to nye forløb i tre profiler. Krav om nul fejl, nul skips og nul retries er bevaret.

Optageråd er udviklet ud fra [Niantics dokumentation](https://www.nianticspatial.com/docs/scaniverse/techniques/) og [Apples beskrivelse af native miljørekonstruktion](https://developer.apple.com/documentation/arkit/visualizing-and-interacting-with-a-reconstructed-scene). Illustrationerne er kodebaserede vejledningsbilleder, ikke fotos eller dokumentation af faktiske scanninger.

Browseremulering, CI, privat publicering og fysisk iPhone skal registreres særskilt i leveringsrapporten. Installation, virkelig kameraoptagelse og LiDAR på iPhone 14 Pro Max er ikke dokumenteret alene ved disse tests. Ingen native kildeændring, signering, merge, Pages- eller Lovable-udgivelse følger med denne ændring.
