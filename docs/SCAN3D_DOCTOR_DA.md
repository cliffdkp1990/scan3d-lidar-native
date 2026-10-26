# Scan3D Doctor · dansk brugsvejledning
Opdateret 26. oktober 2026.

Scan3D Doctor kan **ikke** automatisk rette vilkårlige Swift-, Metal-, kamera- eller LiDAR-fejl. Det diagnosticerer fejlede GitHub Actions-runs, gemmer en JSON-rapport og opretter/opdaterer en PR-specifik reparationsopgave. Kun klart identificerede, midlertidige fejl under runner-opsætning eller checkout genkøres højst **én gang**.

## Hvor ligger den aktuelle version?
- [PR #1: Metal-scanner](https://github.com/cliffdkp1990/scan3d-lidar-native/pull/1), base `main`
- [PR #6: Scan3D Doctor](https://github.com/cliffdkp1990/scan3d-lidar-native/pull/6), base PR #1's branch
- Gamle PR #2–#5 er lukket uden merge. Ret ikke den udfasede RealityKit-resultatviewer.

## Sikkerhed
- Uden `--apply` læser scriptet kun, og rapporten gemmes lokalt.
- Med `--apply` kan scriptet, for den præcise aktuelle PR-head-SHA, genkøre en verificeret transient checkout-fejl én gang. Reelle UI-, Swift- og Xcode-fejl giver ikke blind retry.
- For andre fejlkategorier kan Doctor oprette et issue eller tilføje en kommentar uden at overskrive eksisterende menneskelige noter.
- Ingen ændring af appkode, PR-merge, deploy, Apple-signering, TestFlight eller påstand om fysisk LiDAR-verifikation.
- Beskyttelsen af `main` er aktiv med PR-krav og obligatorisk CI-check. Doctor har ingen bypass-rettighed.

## Fra iPhone
Efter at PR #1 og derefter PR #6 **er særskilt gennemgået og integreret**, åbner du [GitHub Actions](https://github.com/cliffdkp1990/scan3d-lidar-native/actions) og vælger **Scan3D Doctor - safe automatic CI triage**. `Run workflow` starter manuel diagnose. Ved fejl i normal Scan3D-CI starter `workflow_run` automatisk, men **først når Doctor-workflowet findes på standardbranchen `main`**.

Der er ikke aktiveret noget automatisk workflow på `main` alene ved at oprette draft PR #6.

## Windows (valgfrit)
Installer Python 3 og GitHub CLI, og log på med `gh auth login`:

```powershell
python scripts/scan3d_doctor.py --run-id latest
python scripts/scan3d_doctor.py --run-id latest --apply
```

`scan3d-doctor-status.json` gemmes i den aktuelle mappe. Den første kommando læser kun.

## Håndtering af reelle UI-fejl
Den aktuelle viewer bruger **MetalKit**, ikke den ældre RealityKit-resultatviewer. Ved fejl: læs første konkrete fejl i GitHub Actions, gennemgå screenshots fra `scan3d-native-ui-evidence`, find koden i `GeometryMetalRenderer.swift` eller det relevante kamera-/UI-modul og test en **ny commit**. Forøg ikke bare timeout eller slet assertions for at få en grøn status.

### Godkendelseskriterier
Seneste commit i PR #6 skal have bestået hele native CI og Python-regressionstestene. Fysisk LiDAR-scanning og signeret iPhone-installation er separate, stadig manglende acceptancetests. Ingen merge eller udgivelse som del af fejlfinding.
