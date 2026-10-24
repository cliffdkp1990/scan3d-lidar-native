# Scan3D LiDAR

Native LiDAR-capable iPhone prototype using SwiftUI, ARKit, RealityKit and Vision (iOS 17+; physical acceptance target: iPhone 14 Pro Max). Ordinary iPhone 13 has no LiDAR and cannot use this capture path. The source captures guided photos, samples real LiDAR depth and exports PLY/OBJ. Photo-based reconstruction, video recording and a true result model viewer remain planned.

Automatic photos are enabled by default after locking a target. An uncovered position must pass tracking, distance, aiming and translation-stability checks; the exact frame is revalidated before capture. This is not yet a sharpness/exposure quality detector. Retakes remain manual. A save error disables automatic capture. Backgrounding, sheets and interruptions suspend capture. Resume after a paused camera requires a new target/project rather than assuming the old world coordinates are valid.

Mine scanninger opens persistent projects, photo thumbnails, full photos, file integrity checks and individual photo/PLY/OBJ sharing. Assets and SHA-256 records are written before an atomic manifest commit. Retakes preserve originals. Each accepted photo persists the current point cloud; this protects geometry from a later reset. JPEG/thumbnail encoding and capture file writes run on a serial background queue. The library reopens saved data read-only; it does not resume an old AR mission. It does not yet archive/import an entire project. Old Scan3DPhotos/Scan3DLiDARExports folders remain intact and accessible through Files.

The source lives directly in `Scan3DLiDAR/`. The workflow compiles that source; it does not download an external source ZIP. See GitHub Actions and the pull request checks for the current build result. CI runs for pull requests and pushes to main, avoiding duplicate branch/PR builds. Physical iPhone installation, signing and LiDAR acceptance tests remain outstanding.

For Mac: install Xcode and XcodeGen, run `xcodegen generate` inside `Scan3DLiDAR`, then open the generated Xcode project. Sign with your own Apple team to run on a physical supported device. An unsigned Simulator build does not install on an iPhone.

The maintained app plan is `docs/APPPLAN_DA.md`, included automatically by the registered local GitHub Flow profile. No per-update ZIP download or manual GitHub upload is needed.
