"""Offline regression tests for the strict native-commit-bound installer bundler."""
from pathlib import Path
import importlib.util
import io
import json
import unittest
import zipfile

script = Path(__file__).with_name("build_verified_package.py")
spec = importlib.util.spec_from_file_location("scan3d_bundle", script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
SHA = "a" * 40
OTHER = "b" * 40
HASH = "c" * 64


def artifact(files: dict[str, bytes]) -> bytes:
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w") as z:
        for name, data in files.items():
            z.writestr(name, data)
    return out.getvalue()


class PinnedBuildTests(unittest.TestCase):
    def test_pin_rewrites_only_exact_metadata_lines(self):
        template = (
            "$Scan3DCommit = '" + ("1" * 40) + "'\r\n"
            "$Scan3DSHA256 = '" + ("2" * 64) + "'\r\n"
            "Do not change example commit " + ("1" * 40) + "\r\n"
        )
        result = module.pinned_script(template, SHA, HASH)
        self.assertIn("$Scan3DCommit = '" + SHA + "'", result)
        self.assertIn("$Scan3DSHA256 = '" + HASH + "'", result)
        self.assertIn("example commit " + ("1" * 40), result)
        self.assertEqual(result.count(SHA), 1)
        self.assertEqual(result.count(HASH), 1)

    def test_iphone_handoff_requires_wifi_and_localdevvpn(self):
        guide = module.iphone_handoff_text(SHA, HASH)
        self.assertIn("Wi-Fi", guide)
        self.assertIn("LocalDevVPN", guide)
        self.assertIn("Choose Server", guide)
        self.assertIn("Gentag ikke Apple-login", guide)
        self.assertIn(SHA, guide)
        self.assertIn(HASH, guide)
        with self.assertRaises(ValueError):
            module.iphone_handoff_text("short", HASH)

    def test_windows_launcher_has_explicit_folder_and_no_auto_install(self):
        text = script.with_name("Start-Scan3D.cmd").read_text(encoding="utf-8")
        self.assertIn('-PackageFolder "%~dp0."', text)
        self.assertNotIn("-InstallAltServer", text)
        self.assertIn("IKKE automatisk installeret", text)

    def test_duplicate_or_missing_pin_rejected(self):
        good = "$Scan3DCommit = '" + SHA + "'\n$Scan3DSHA256 = '" + HASH + "'\n"
        for candidate in ("", good + good,
                          "$Scan3DCommit = 'garbled'\n$Scan3DSHA256 = '" + HASH + "'\n",
                          "$Scan3DCommit = '" + SHA + "'\n"):
            with self.subTest(candidate=candidate[:20]), self.assertRaises(ValueError):
                module.pinned_script(candidate, OTHER, HASH)

    def test_full_source_sha_required(self):
        with self.assertRaises(ValueError):
            module.pinned_script("", "shortsha", HASH)

    def test_unexpected_artifact_entries_rejected(self):
        body = artifact({"SCAN3D_PACKAGE.json": b"{}", "Scan3D-unsigned.ipa": b"ipa",
                         "credentials.txt": b"secret"})
        with self.assertRaises(ValueError):
            module.verified_payload(body, SHA)

    def test_stale_artifact_sha_rejected_before_ipa_read(self):
        manifest = json.dumps({"schemaVersion": 1, "sourceCommit": OTHER}).encode()
        body = artifact({"SCAN3D_PACKAGE.json": manifest, "Scan3D-unsigned.ipa": b"ipa"})
        with self.assertRaisesRegex(ValueError, "source"):
            module.verified_payload(body, SHA)

    def test_malformed_manifest_rejected(self):
        body = artifact({"SCAN3D_PACKAGE.json": b"not json", "Scan3D-unsigned.ipa": b"ipa"})
        with self.assertRaises(ValueError):
            module.verified_payload(body, SHA)

    def test_directory_traversal_rejected(self):
        with self.assertRaises(ValueError):
            module.checked_archive(artifact({"../Scan3D.ipa": b"unsafe"}))

    def test_modified_ipa_digest_rejected(self):
        manifest = {
            "schemaVersion": 1, "sourceCommit": SHA,
            "bundleIdentifier": "dk.scan3dstudio.lidar",
            "platform": "iOS-device-arm64", "configuration": "Release",
            "installableAsIs": False, "physicalDeviceTested": False,
            "documentsVisibleInFilesApp": True,
            "marketingVersion": "0.1.0", "buildVersion": "1",
            "bytes": 3, "sha256": "0" * 64,
        }
        body = artifact({"SCAN3D_PACKAGE.json": json.dumps(manifest).encode(),
                         "Scan3D-unsigned.ipa": b"ipa"})
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            module.verified_payload(body, SHA)


if __name__ == "__main__":
    unittest.main()
