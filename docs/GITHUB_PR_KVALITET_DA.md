# GitHub-regler for Scan3D · version 2026-10-25

## Faste branches og PR-rækkefølge
1. PR #1 `codex/sync-scan3d` → `main`: native app og feature-kode, **draft**.
2. PR #3 `fix/native-geometry-ui-and-ci-20261025` → `codex/sync-scan3d`: RealityKit/UI-rettelser, **draft**.
3. PR #4 `ci/scan3d-automatic-quality-report-20261025` → `fix/native-geometry-ui-and-ci-20261025`: scripts/CI-automatisering, **draft**.
4. PR #2 er lukket **uden merge**: samme build-sikkerhedskontrol blev indført i PR #3/#4.

**Ingen PR merges automatisk; ingen automatisk deploy, TestFlight, signering, Lovable eller Pages.**

## Revisionssikker test
- Hver PR har sin egen verificerede HEAD-SHA og en separat CI-kørsel.
- GitHub kan teste et *midlertidigt merge-commit* for PR'er. Både faktisk checkout SHA og PR-head SHA skal stå i rapporten. Grøn PR-merge-CI er ikke en selvstændig attest for den rå PR-head.
- Tests fra en gammel SHA tæller aldrig som godkendelse af en ny SHA.
- Fejlede, annullerede, ukendte eller sprunget-over testtrin er **ikke grønne**.
- `Scan3D-lidar`-workflow kører for alle PR'er, også ændringer i `scripts/` og `docs/`.
- Builds til Debug Simulator, Release Simulator og unsigned iPhone-target registreres hver for sig. **Unsigned build kan ikke installeres på en iPhone**.
- `scan3d-ci-status.json`, miljøbeviser, logs og native screenshots bevares som kortlivede artefakter for fejlfinding.

## Fejlhåndtering
- Find det første fejlede jobtrin og dets første konkrete fejl. Genstart ikke blindt.
- Hvis en visuel RealityKit-test fejler, sammenhold UI-testens screenshots og `scan3d-viewer-trace.log`; undersøg først appens rendering før test-tidsgrænser udvides.
- Gentagne grøn/rød-resultater på identisk SHA betyder potentielt ustabil test/runner. Marker som *flaky*, ikke som permanent rettet.
- Opdatér kode, test og tilhørende status i den PR der ejer den relevante fil. For stacked PR'er: synkroniser historie via almindeligt merge, ikke ved at overskrive andres commits.
- Udfør fysisk test af kamera, LiDAR, video, lagring og 3D-rekonstruktion på faktisk LiDAR-iPhone. Simulatoren har kun syntetiske sensordata.

## Merge-/releasekrav
- Grøn CI på den **seneste præcise revision**.
- Kvalitetsgennemgang af test- og kodeændringer; ingen slækkede assertioner uden dokumenteret grund.
- Bekræftet repository/branch protection og obligatoriske statuschecks i GitHub-repoindstillinger. Dette kræver særskilt verificering.
- Dokumenteret fysisk iPhone-test og, før installation, Apple-signering/TestFlight invitation.
- Opdatér ikke `main`, Pages, Lovable eller produktion som del af fejlfinding.

## Oprettelse af nye PR'er
- Opret fra seneste opdaterede basebranch.
- Hold PR'en til én teknisk leverance. PR'er over andre feature-PR'er bruger stacked base, ikke `main`.
- Afvent CI, læs præcis SHA i Actions. Luk kun ældre overlappende PR'er med begrundelse og krydslink.
- Fremtidige software-/runneropdateringer kontrolleres ud fra dokumenteret værktøjsversion; ingen automatisk antagelse om kompatibilitet.
