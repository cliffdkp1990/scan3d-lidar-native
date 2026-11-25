#!/usr/bin/env python3
"""Build a verified unsigned Scan3D install handoff from a successful native CI artifact.

Offline only: no Apple signing, device installation, network, secret access or release.
The expected SHA MUST come from a trusted successful GitHub Actions workflow_run event.
"""
from __future__ import annotations
import argparse
import hashlib
import io
import json
import pathlib
import plistlib
import re
import zipfile

MAX_IPA_BYTES = 256 * 1024 * 1024
SOURCE_RE = re.compile(r"^[a-f0-9]{40}$")
SHA256_RE = re.compile(r"^[a-f0-9]{64}$")
REQUIRED = {"SCAN3D_PACKAGE.json", "Scan3D-unsigned.ipa"}
APP_PREFIX = "Payload/Scan3DLiDAR.app/"
COMMIT_MARKER = "$Scan3DCommit = '"
SHA_MARKER = "$Scan3DSHA256 = '"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def pinned_script(template: str, source: str, digest: str) -> str:
    """Refuse stale/unexpected scripts rather than replacing unrelated strings."""
    if not SOURCE_RE.fullmatch(source) or not SHA256_RE.fullmatch(digest):
        raise ValueError("A complete source SHA and package digest are required")
    lines = template.splitlines(keepends=True)
    for marker, replacement, length in ((COMMIT_MARKER, source, 40), (SHA_MARKER, digest, 64)):
        matches = [i for i, line in enumerate(lines) if line.startswith(marker)]
        if len(matches) != 1:
            raise ValueError(f"One exact installer marker required: {marker}")
        index = matches[0]
        line = lines[index]
        match = re.fullmatch(re.escape(marker) + r"([a-f0-9]{" + str(length) + r"})'(\r?\n)?", line)
        if not match:
            raise ValueError("Installer template pin is malformed")
        lines[index] = marker + replacement + "'" + (match.group(2) or "")
    return "".join(lines)


def checked_archive(data: bytes, *, exact_names: set[str] | None = None) -> zipfile.ZipFile:
    if not data or len(data) > MAX_IPA_BYTES + 32 * 1024 * 1024:
        raise ValueError("Archive size outside allowed bounds")
    archive = zipfile.ZipFile(io.BytesIO(data), "r")
    names = [item.filename for item in archive.infolist()]
    if not names or len(names) != len(set(names)):
        archive.close()
        raise ValueError("Empty archive or duplicate ZIP members")
    if exact_names is not None and set(names) != exact_names:
        archive.close()
        raise ValueError("Unexpected artifact ZIP layout")
    for item in archive.infolist():
        name = item.filename
        if name.startswith("/") or "\\" in name or any(x in ("", ".", "..") for x in name.split("/")):
            archive.close()
            raise ValueError("Unsafe archive member path")
        mode = (item.external_attr >> 16) & 0o170000
        if mode == 0o120000:
            archive.close()
            raise ValueError("Symlink in native artifact")
    if archive.testzip() is not None:
        archive.close()
        raise ValueError("Archive CRC check failed")
    return archive


def verified_payload(artifact: bytes, expected_sha: str) -> tuple[dict, bytes]:
    if not SOURCE_RE.fullmatch(expected_sha):
        raise ValueError("Expected SHA must be an exact 40-character Git commit")
    with checked_archive(artifact, exact_names=REQUIRED) as pkg:
        receipt_data = pkg.read("SCAN3D_PACKAGE.json")
        if len(receipt_data) > 2_000_000:
            raise ValueError("Manifest too large")
        manifest = json.loads(receipt_data.decode("utf-8"))
        ipa_info = pkg.getinfo("Scan3D-unsigned.ipa")
        if ipa_info.file_size > MAX_IPA_BYTES:
            raise ValueError("IPA exceeds safety limit")
        ipa = pkg.read("Scan3D-unsigned.ipa")
    if manifest.get("schemaVersion") != 1 or manifest.get("sourceCommit") != expected_sha:
        raise ValueError("IPA source does not equal the successful native run's SHA")
    if (manifest.get("bundleIdentifier") != "dk.scan3dstudio.lidar"
            or manifest.get("platform") != "iOS-device-arm64"
            or manifest.get("configuration") != "Release"
            or manifest.get("installableAsIs") is not False
            or manifest.get("physicalDeviceTested") is not False
            or manifest.get("documentsVisibleInFilesApp") is not True):
        raise ValueError("IPA platform, signing or Files access assertions failed")
    version = manifest.get("marketingVersion")
    build = manifest.get("buildVersion")
    if not isinstance(version, str) or not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Missing app version")
    if not isinstance(build, str) or not re.fullmatch(r"\d+(?:\.\d+){0,2}", build):
        raise ValueError("Missing app build number")
    if manifest.get("bytes") != len(ipa) or not SHA256_RE.fullmatch(str(manifest.get("sha256", ""))):
        raise ValueError("IPA size or digest missing")
    if sha256(ipa) != manifest["sha256"]:
        raise ValueError("IPA SHA-256 mismatch")
    records = manifest.get("files")
    if not isinstance(records, list) or not (1 <= len(records) <= 10_000):
        raise ValueError("Invalid internal file manifest")
    with checked_archive(ipa) as inner:
        expected_names = {r.get("path") for r in records if isinstance(r, dict)}
        if len(expected_names) != len(records) or set(inner.namelist()) != expected_names:
            raise ValueError("Internal IPA paths don't match manifest")
        for record in records:
            name = record["path"]
            if not isinstance(name, str) or not name.startswith(APP_PREFIX):
                raise ValueError("Unexpected iOS app file location")
            if name.lower().endswith((".p8", ".p12", ".pem", ".mobileprovision", ".key")):
                raise ValueError("Unexpected signing secrets")
            data = inner.read(name)
            if record.get("bytes") != len(data) or record.get("sha256") != sha256(data):
                raise ValueError("Internal IPA content hash mismatch")
        plist = plistlib.loads(inner.read(APP_PREFIX + "Info.plist"))
        expected_plist = {
            "CFBundleIdentifier": manifest["bundleIdentifier"],
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build,
            "DTPlatformName": "iphoneos",
            "UIFileSharingEnabled": True,
            "LSSupportsOpeningDocumentsInPlace": True,
        }
        if any(plist.get(k) != v for k, v in expected_plist.items()):
            raise ValueError("Built Info.plist contradicts actual manifest")
    return manifest, ipa


def iphone_handoff_text(source: str, digest: str) -> str:
    """Short, on-device AltStore Classic instructions bound to a verified IPA."""
    if not SOURCE_RE.fullmatch(source) or not SHA256_RE.fullmatch(digest):
        raise ValueError("Complete source and IPA digests are required")
    return (
        "Scan3D iPhone: Apple-signering og enhedsgodkendelse er paakraevet.\n"
        "AltStore Classic -> My Apps -> + -> vaelg Scan3D-unsigned.ipa.\n"
        "Remote AltServer kraever Wi-Fi (ikke 5G/mobildata) OG tilsluttet LocalDevVPN.\n"
        "Ved 'couldn't reach remote AltServer': tjek Wi-Fi + LocalDevVPN, og genstart evt. telefonen.\n"
        "Ved ugyldigt svar eller utilgaengelig server: AltStore Settings -> Remote AltServer -> Choose Server.\n"
        "Gentag ikke Apple-login, hvis fejlen kun handler om serverforbindelsen.\n"
        "Del aldrig Apple-adgangskoder i ChatGPT eller i en fejlrapport.\n"
        "Ingen usigneret IPA kan installeres direkte fra Filer.\n"
        "Efter installation: Scan3D -> Test min LiDAR; test gem og genaabn projekt.\n"
        f"Godkendt kilde: {source}\n"
        f"IPA SHA-256: {digest}\n"
    )


def artifact_bytes(artifact: pathlib.Path) -> bytes:
    if artifact.is_dir():
        # actions/download-artifact extracts exactly these two files.
        entries = list(artifact.iterdir())
        if {entry.name for entry in entries} != REQUIRED or len(entries) != len(REQUIRED):
            raise ValueError("Downloaded native artifact has extra or missing files")
        if any(entry.is_symlink() or not entry.is_file() for entry in entries):
            raise ValueError("Native artifact contains a link or non-file")
        if (artifact / "Scan3D-unsigned.ipa").stat().st_size > MAX_IPA_BYTES:
            raise ValueError("Native iPhone IPA too large")
        output = io.BytesIO()
        with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for name in sorted(REQUIRED):
                archive.writestr(name, (artifact / name).read_bytes())
        return output.getvalue()
    return artifact.read_bytes()


def build(artifact: pathlib.Path, installer_dir: pathlib.Path,
          expected_sha: str, output: pathlib.Path) -> dict:
    manifest, ipa = verified_payload(artifact_bytes(artifact), expected_sha)
    folder = installer_dir
    required_files = ("Start-Scan3D.cmd", "Start-Scan3D.ps1",
                      "Test-Scan3D.ps1", "README_DA.md")
    assets = {name: (folder / name).read_bytes() for name in required_files}
    template = assets["Start-Scan3D.ps1"].decode("utf-8")
    assets["Start-Scan3D.ps1"] = pinned_script(
        template, expected_sha, manifest["sha256"]).encode("utf-8-sig")
    # The included human guide originally described PR23. Update immutable pins
    # in generated bundles so a newer main build is never advertised as PR23.
    guide = assets["README_DA.md"].decode("utf-8")
    guide = guide.replace("3863502b6aa9929bbe6fb204e0c71ed05e1ef0bb", expected_sha)
    guide = guide.replace("8c1987f7a3bae83742d95025c2c7ee219b711ab446a02948141871747e536fac",
                          manifest["sha256"])
    guide = guide.replace("iOS-build fra PR #23", "præcist verificeret native iOS-build")
    assets["README_DA.md"] = guide.encode("utf-8")
    assets["Scan3D-unsigned.ipa"] = ipa
    assets["SCAN3D_PACKAGE.json"] = (
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    assets["START_HER_iPHONE.txt"] = iphone_handoff_text(expected_sha, manifest["sha256"]).encode("utf-8")
    if output.exists():
        raise FileExistsError("Never silently overwrite an installation package")
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_DEFLATED) as archive:
        for filename, data in sorted(assets.items()):
            archive.writestr(filename, data)
    receipt = {
        "sourceCommit": expected_sha,
        "ipaSHA256": manifest["sha256"],
        "ipaBytes": len(ipa),
        "appVersion": manifest["marketingVersion"],
        "sha256": sha256(output.read_bytes()),
        "bundleBytes": output.stat().st_size,
        "signed": False, "installedOnPhone": False,
        "physicalLiDARVerified": False,
        "entries": list(sorted(assets)),
    }
    receipt_path = output.with_suffix(".json")
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    return receipt


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifact", type=pathlib.Path, required=True)
    parser.add_argument("--installer-dir", type=pathlib.Path, required=True)
    parser.add_argument("--expected-sha", required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    result = build(args.artifact, args.installer_dir, args.expected_sha, args.output)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
