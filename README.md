# Scan3D LiDAR

Native iPhone 14 Pro Max prototype using SwiftUI, ARKit, RealityKit and Vision. Existing source captures guided photos, samples real LiDAR depth and exports PLY/OBJ. Photo-based reconstruction, video recording and a model library are planned, not implemented in this baseline.

The source lives directly in `Scan3DLiDAR/`. The workflow compiles that source; it does not download an external source ZIP. This prepared workflow has not yet been run on GitHub. The recovered baseline's earlier Simulator build passed; physical iPhone installation, signing and LiDAR acceptance tests remain outstanding.

For Mac: install Xcode and XcodeGen, run `xcodegen generate` inside `Scan3DLiDAR`, then open the generated Xcode project. Sign with your own Apple team to run on a physical supported device. An unsigned Simulator build does not install on an iPhone.

The maintained app plan is `docs/APPPLAN_DA.md`, included automatically by the registered local GitHub Flow profile. No per-update ZIP download or manual GitHub upload is needed.
