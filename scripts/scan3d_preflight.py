#!/usr/bin/env python3
"""Fast dependency-free checks. Not a substitute for Xcode, LiDAR or iPhone testing."""
from pathlib import Path
import argparse
import re

REQUIRED = [
    "Scan3DLiDAR/project.yml",
    "Scan3DLiDAR/Sources/ScanEngine.swift",
    "Scan3DLiDAR/Sources/VideoRecorder.swift",
    "Scan3DLiDAR/Sources/GeometryViewer.swift",
    "Scan3DLiDAR/Sources/ProjectStore.swift",
    "Scan3DLiDAR/UITests/CaptureStudioUITests.swift",
    ".github/workflows/scan3d-lidar.yml",
]

def inspect(root: Path) -> list[str]:
    failures = []
    for name in REQUIRED:
        path = root / name
        if not path.is_file():
            failures.append(f"Missing required file: {name}")
        elif path.stat().st_size == 0:
            failures.append(f"Empty required file: {name}")
    if failures:
        return failures
    project = (root / REQUIRED[0]).read_text(encoding="utf-8")
    source = (root / REQUIRED[1]).read_text(encoding="utf-8")
    tests = (root / REQUIRED[-2]).read_text(encoding="utf-8")
    workflow = (root / REQUIRED[-1]).read_text(encoding="utf-8")
    if not re.search(r"deploymentTarget:\s*\n\s*iOS:\s*['\"]?17", project):
        failures.append("Review deployment target and hardware test matrix")
    if "CODE_SIGNING_ALLOWED=NO" not in workflow:
        failures.append("Unsigned CI build policy missing")
    if "contents: read" not in workflow:
        failures.append("Least-privilege GitHub Actions permission missing")
    if "pull_request:" not in workflow:
        failures.append("Pull request CI trigger missing")
    if "SCAN3D_STUDIO_FIXTURE" not in tests:
        failures.append("Explicit synthetic fixture guard missing")
    if "func captureCurrentFrame()" not in source:
        failures.append("Camera capture entry point missing")
    if "frame.smoothedSceneDepth.flatMap { Self.middleDepth($0.depthMap) }" in source:
        failures.append("Old CVPixelBuffer.flatMap Swift error reintroduced")
    return failures

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".")
    args = parser.parse_args()
    errors = inspect(Path(args.root))
    for error in errors:
        print(f"::error::{error}")
    if errors:
        return 1
    print("PASS: source tree, signing policy, synthetic fixtures, PR checks")
    print("NOTE: native compile, LiDAR capture and real 3D rendering are not checked here")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
