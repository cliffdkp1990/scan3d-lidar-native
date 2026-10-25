# Scan3D GitHub Doctor

Et sikkert værktøj til automatisk fejldiagnose. Koden kan **ikke automatisk rette alle Swift-, UI- eller LiDAR-fejl**. Den opdager dem og opretter en konkret reparationsopgave; kun tydeligt midlertidige GitHub-runnerfejl genkøres, højst én gang.

## Status og sikkerhed

- **Læsetilstand som standard.** `--apply` aktiverer kun en enkelt sikker genkørsel eller et PR-specifikt GitHub-issue.
- Kun repository `cliffdkp1990/scan3d-lidar-native`. Genkørsel kræver nøjagtigt match mellem PR-head-SHA og run-SHA.
- `run_attempt` skal være **1**. Samme fejl bliver ikke genkørt uendeligt.
- UI, RealityKit, Xcode- og Swift-kompileringsfejl bliver **ikke** genkørt som om de var infrastrukturfejl.
- Ingen automatisk kodeændring, merge, deploy, TestFlight, signering eller ændring af DroneHub.
- Faktisk iPhone/LiDAR-test forbliver `not_verified`, uanset hvad Simulator-builds siger.

## Fra iPhone

Når PR'en efter godkendelse er integreret på repositoryets **default branch**, kan du åbne:

https://github.com/cliffdkp1990/scan3d-lidar-native/actions

Vælg **Scan3D Doctor - safe automatic CI triage → Run workflow** og indtast valgfrit det fejlede run-id. Lades feltet tomt, analyseres seneste fejlede Scan3D-run.

GitHub vil også selv køre værktøjet, **når** den normale scanner-CI afsluttes med fejl. Bemærk at `workflow_run` kræver, at Doctor-workflowet findes på **main**; dette fungerer ikke permanent alene fra en draft-PR.

## Windows, GitHub CLI og Python

Kræver Python 3 og GitHub CLI (`gh`), logget ind via `gh auth login`:

```powershell
python scripts/scan3d_doctor.py --run-id latest
python scripts/scan3d_doctor.py --run-id 40202617630
python scripts/scan3d_doctor.py --run-id latest --apply
```

Første to kommandoer læser kun. Sidste tillader en afgrænset genkørsel eller en fejlopgave. Rapporter gemmes i `scan3d-doctor-status.json`.

## Sådan reparerer vi reelle appfejl

Seneste verificerede Scan3D-fejl: `testActualStoredGeometryRendererAndControls` fejlede på kontrol af faktiske skærmpixels efter reset. Ret GeometryViewer.swift og gentest med Xcode screenshots og trace. En automatisk genkørsel er **ikke** en kode-rettelse.

## Merge-rekkefølge

- PR #1: den native udviklingsversion
- PR #3: kode-/UI-rettelser
- PR #4: CI/rapportering
- Denne PR: Doctor, oven på PR #4

Ingen automatisk merge af denne kæde. Når relevant CI er grøn på nyeste SHA, review PR'erne og integrér i kontrolleret rækkefølge. Branch protection kræver evt. brugeropsætning.
