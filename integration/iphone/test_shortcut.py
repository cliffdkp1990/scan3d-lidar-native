import copy
import json
import plistlib
import struct
import tempfile
import unittest
from pathlib import Path

from build_shortcut import actions, build, validate_workflow, workflow
from sign_shortcut import check_archive, sign, storage_url


class ShortcutTests(unittest.TestCase):
    def test_roundtrip_and_idempotent_build(self):
        with tempfile.TemporaryDirectory(dir=Path.cwd()) as temp:
            folder = Path(temp)
            first = build(folder)
            self.assertEqual(first, build(folder))
            validate_workflow(plistlib.loads((folder / "Scan3D-Forny.UNSIGNED.plist").read_bytes()))
            self.assertEqual(first["status"], "unsigned-draft")
            for key in ("appleSigningPerformed", "uploaded", "installedOnPhone",
                        "scheduledOnPhone", "renewalVerified", "physicalLiDARVerified"):
                self.assertIs(first[key], False)

    def test_changed_destination_is_preserved(self):
        with tempfile.TemporaryDirectory(dir=Path.cwd()) as temp:
            file = Path(temp) / "Scan3D-Forny.UNSIGNED.plist"
            file.write_text("different", encoding="utf-8")
            with self.assertRaises(FileExistsError):
                build(Path(temp))
            self.assertEqual(file.read_text(), "different")
            self.assertFalse((Path(temp) / "SHORTCUT_DRAFT.json").exists())

    def test_foreign_app_or_hidden_network_action_is_rejected(self):
        for index in range(4):
            candidate = copy.deepcopy(workflow())
            candidate["WFWorkflowActions"][index]["WFWorkflowActionIdentifier"] = "foreign.action"
            with self.assertRaises(ValueError):
                validate_workflow(candidate)
        candidate = workflow()
        candidate["WFWorkflowActions"].append({"WFWorkflowActionIdentifier": "is.workflow.actions.downloadurl"})
        with self.assertRaises(ValueError):
            validate_workflow(candidate)

    def test_modified_parameters_are_rejected(self):
        for index, params in [(0, {"operation": "toggle"}), (1, {"WFDelayTime": 0}),
                              (2, {"AppIntentDescriptor": {"BundleIdentifier": "com.kdt.livecontainer"}}),
                              (3, {"WFInput": "https://foreign.example"})]:
            candidate = workflow()
            candidate["WFWorkflowActions"][index]["WFWorkflowActionParameters"] = params
            with self.assertRaises(ValueError):
                validate_workflow(candidate)

    def test_no_success_claim_or_disconnect_and_no_private_data(self):
        content = json.dumps(workflow())
        for token in ["RefreshAllIntent", "ControlLocalDevVPNIntent", "altstore-classic://"]:
            self.assertIn(token, content)
        for token in ["notification", "Disconnect", "password", "drive.google.com",
                      "TeamIdentifier", "UDID", "WFVPN", "LiveContainer"]:
            self.assertNotIn(token, content)

    def test_wrapped_descriptor_from_cherri_is_rejected(self):
        candidate = workflow()
        parameters = candidate["WFWorkflowActions"][0]["WFWorkflowActionParameters"]
        descriptor = parameters["AppIntentDescriptor"]
        parameters["AppIntentDescriptor"] = {"Value": descriptor,
                                              "WFSerializationType": "WFDictionaryFieldValue"}
        with self.assertRaises(ValueError):
            validate_workflow(candidate)

    def test_extra_import_questions_or_share_sheet_rejected(self):
        for key, value in [("WFWorkflowImportQuestions", [{"ParameterKey": "password"}]),
                           ("WFWorkflowTypes", ["ActionExtension"])]:
            candidate = workflow()
            candidate[key] = value
            with self.assertRaises(ValueError):
                validate_workflow(candidate)

    def test_signing_requires_explicit_service_approval(self):
        with tempfile.TemporaryDirectory(dir=Path.cwd()) as temp:
            with self.assertRaises(PermissionError):
                sign(Path(temp), approved=False)
            self.assertEqual(list(Path(temp).iterdir()), [])

    def test_signed_download_destination_is_restricted(self):
        self.assertEqual(storage_url("/storage/example/Scan3D Forny.shortcut"),
                         "https://playground.cherrilang.org/storage/example/Scan3D%20Forny.shortcut")
        for bad in ["https://foreign.example/a", "//foreign.example/a", "/storage/../Scan3D Forny.shortcut",
                    "/storage/a/Scan3D Forny.shortcut?secret=yes", "/storage/Scan3D Forny.shortcut#x",
                    "/storage/a\\b/Scan3D Forny.shortcut", "/storage/a\nb/Scan3D Forny.shortcut"]:
            with self.assertRaises(ValueError):
                storage_url(bad)

    def test_archive_exact_payload_and_extra_bytes(self):
        def header(fields):
            return b"AA01" + struct.pack("<H", len(fields) + 6) + fields
        root = header(b"TYP1DPATP\x00\x00MOD2" + bytes(2) + b"MTMT" + bytes(12))
        body = plistlib.dumps(workflow())
        file_header = header(b"TYP1FPATP\x0e\x00Shortcut.wflowMOD2" + bytes(2)
                             + b"MTMT" + bytes(12) + b"DATA" + struct.pack("<H", len(body)))
        archive = root + file_header + body
        self.assertEqual(check_archive(archive), workflow())
        for bad in [archive[:-1], archive + b"extra", archive.replace(b"Shortcut.wflow", b"OtherApp.wflow"),
                    archive.replace(b"com.rileytestut.AltStore", b"com.otherbrand.BadStore")]:
            with self.assertRaises((ValueError, plistlib.InvalidFileException)):
                check_archive(bad)


if __name__ == "__main__":
    unittest.main()
