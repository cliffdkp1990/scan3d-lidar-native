"""Build a reviewable iPhone renewal shortcut; never sign, upload or install it."""
from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
from pathlib import Path

NAME = "Scan3D Forny"
VPN_BUNDLE = "com.jkcoxson.LocalDevVPN"
ALTSTORE_BUNDLE = "com.rileytestut.AltStore"
VPN_INTENT = "ControlLocalDevVPNIntent"
REFRESH_INTENT = "RefreshAllIntent"
CLASSIC_URL = "altstore-classic://"
HANDOFF_URL = "localdevvpn://enable?scheme=altstore-classic"
SOURCE_REVISIONS = {
    "altstore": "bbc10d6964185b75a46c6ddd7476ac08df095308",
    "localdevvpn": "af3fd697803ada4ac2b8d518358f5ab0a534844c",
}


def app_intent(bundle: str, name: str, intent: str) -> dict:
    return {
        "WFWorkflowActionIdentifier": f"{bundle}.{intent}",
        "WFWorkflowActionParameters": {
            "AppIntentDescriptor": {
                "BundleIdentifier": bundle,
                "Name": name,
                "AppIntentIdentifier": intent,
            }
        },
    }


def actions() -> list[dict]:
    # LocalDevVPN's default operation is enable, never toggle. It starts the
    # tunnel asynchronously: five seconds is a delay, not a connection check.
    # AltStore propagates refresh errors, but can also return with zero apps or
    # continue in foreground. Therefore do not add a success message, automatic
    # VPN disconnect, or a claimed new expiration date.
    return [
        app_intent(VPN_BUNDLE, "LocalDevVPN", VPN_INTENT),
        {"WFWorkflowActionIdentifier": "is.workflow.actions.delay",
         "WFWorkflowActionParameters": {"WFDelayTime": 5}},
        app_intent(ALTSTORE_BUNDLE, "AltStore Classic", REFRESH_INTENT),
        {"WFWorkflowActionIdentifier": "is.workflow.actions.openurl",
         "WFWorkflowActionParameters": {"WFInput": CLASSIC_URL}},
    ]


def workflow() -> dict:
    return {
        "WFWorkflowName": NAME,
        "WFWorkflowMinimumClientVersion": 1200,
        "WFWorkflowClientVersion": "2300.0.0",
        "WFWorkflowIcon": {"WFWorkflowIconStartColor": 1440408063,
                           "WFWorkflowIconGlyphNumber": 59764},
        "WFWorkflowInputContentItemClasses": [],
        "WFWorkflowTypes": [],
        "WFWorkflowImportQuestions": [],
        "WFWorkflowActions": actions(),
    }


def validate_workflow(candidate: dict) -> None:
    if candidate.get("WFWorkflowActions") != actions():
        raise ValueError("Unexpected actions or parameters; preserve file for review.")
    if candidate.get("WFWorkflowImportQuestions", []) != []:
        raise ValueError("Unexpected import questions.")
    if candidate.get("WFWorkflowTypes", []) != []:
        raise ValueError("Unexpected invocation modes.")


def build(folder: Path) -> dict:
    folder.mkdir(parents=True, exist_ok=True)
    payload = workflow()
    validate_workflow(payload)
    files = {
        "Scan3D-Forny.UNSIGNED.plist": plistlib.dumps(payload, sort_keys=False),
    }
    # A changed destination is never silently overwritten.
    for name, data in files.items():
        path = folder / name
        if path.exists() and path.read_bytes() != data:
            raise FileExistsError(f"Existing different file: {path}")
    for name, data in files.items():
        (folder / name).write_bytes(data)
    receipt = {
        "name": NAME, "status": "unsigned-draft",
        "sourceRevisions": SOURCE_REVISIONS,
        "requirements": ["LocalDevVPN 1.3+ with approved VPN configuration",
                         "AltStore Classic 2.3.1 (PAL) with pairing and Apple login",
                         "Wi-Fi", "Scan3D already installed in Classic"],
        "handoffUrl": HANDOFF_URL,
        "appleSigningPerformed": False, "uploaded": False,
        "installedOnPhone": False, "scheduledOnPhone": False,
        "renewalVerified": False, "physicalLiDARVerified": False,
        "files": [{"file": name, "bytes": len(data),
                   "sha256": hashlib.sha256(data).hexdigest()}
                  for name, data in files.items()],
    }
    (folder / "SHORTCUT_DRAFT.json").write_text(
        json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return receipt


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--validate-plist", type=Path)
    args = parser.parse_args()
    if args.validate_plist:
        validate_workflow(plistlib.loads(args.validate_plist.read_bytes()))
        print(json.dumps({"structureMatches": True, "phoneTested": False}))
    elif args.output:
        print(json.dumps(build(args.output), ensure_ascii=False, indent=2))
    else:
        parser.error("Supply --output or --validate-plist")


if __name__ == "__main__":
    main()
