"""Opt-in Cherri signing and exact payload readback; no Apple account or IPA."""
from __future__ import annotations

import argparse
import hashlib
import http.cookiejar
import json
import plistlib
import struct
import urllib.parse
import urllib.request
from pathlib import Path

from build_shortcut import NAME, build, validate_workflow

HOST = "https://playground.cherrilang.org"
MAX_BYTES = 2 * 1024 * 1024


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        raise ValueError("Unexpected redirect; nothing installed or published.")


def storage_url(response: str) -> str:
    path = response.strip()
    url = urllib.parse.urlsplit(HOST + path)
    if (not path.startswith("/storage/") or not path.endswith("/Scan3D Forny.shortcut")
            or url.netloc != "playground.cherrilang.org" or url.query or url.fragment
            or ".." in path.split("/") or "\\" in path or any(ord(c) < 32 for c in path)):
        raise ValueError("Unexpected signed-file destination.")
    return urllib.parse.quote(HOST + path, safe="/:")


def bounded_read(response) -> bytes:
    value = response.read(MAX_BYTES + 1)
    if len(value) > MAX_BYTES:
        raise ValueError("Unexpected response size.")
    return value


def check_archive(plain: bytes) -> dict:
    # Accept only the observed AA01 root-directory + single Shortcut.wflow
    # archive, with no trailing bytes or additional files. Unsupported formats
    # stop; they are never guessed, unpacked to disk, or called verified.
    if len(plain) < 12 or plain[:4] != b"AA01":
        raise ValueError("Unsupported Apple Archive.")
    first = struct.unpack_from("<H", plain, 4)[0]
    if first != 39 or first + 6 > len(plain) or plain[first:first + 4] != b"AA01":
        raise ValueError("Invalid archive root.")
    if (plain[6:17] != b"TYP1DPATP\x00\x00" or plain[17:21] != b"MOD2"
            or plain[23:27] != b"MTMT"):
        raise ValueError("Unexpected root entry.")
    size = struct.unpack_from("<H", plain, first + 4)[0]
    if size != 59 or first + size > len(plain):
        raise ValueError("Invalid archive file header.")
    header = plain[first:first + size]
    body = plain[first + size:]
    if (header[6:31] != b"TYP1FPATP\x0e\x00Shortcut.wflow"
            or header[31:35] != b"MOD2" or header[37:41] != b"MTMT"
            or header[-6:-2] != b"DATA" or struct.unpack("<H", header[-2:])[0] != len(body)):
        raise ValueError("Unexpected archive file or extra payload.")
    candidate = plistlib.loads(body)
    validate_workflow(candidate)
    return candidate


def verify_signed_bytes(data: bytes) -> dict:
    if not 16 <= len(data) <= MAX_BYTES or data[:4] != b"AEA1":
        raise ValueError("Not an AEA shortcut container.")
    # This is payload inspection, not cryptographic signature verification.
    # Apple/iOS must still accept the signature during actual import.
    import lzfse
    start = data.find(b"bvxn")
    if start < 12:
        raise ValueError("Unsupported compression/container profile.")
    plain = lzfse.decompress(data[start:])
    if len(plain) > MAX_BYTES:
        raise ValueError("Unexpected decoded size.")
    check_archive(plain)
    return {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
            "exactFourActionsMatch": True, "archiveFiles": ["Shortcut.wflow"],
            "signatureAcceptedOnIPhone": False, "renewalVerified": False,
            "physicalLiDARVerified": False}


def sign(folder: Path, approved: bool) -> dict:
    if not approved:
        raise PermissionError("Explicit approval for Cherri/HubSign transfer is required.")
    # Ensure the decoder is present before any external write.
    import lzfse  # noqa: F401
    folder = folder.resolve()
    signed = folder / "Scan3D Forny.shortcut"
    receipt_path = folder / "SIGNED_SHORTCUT.json"
    if signed.exists():
        verified = verify_signed_bytes(signed.read_bytes())
        if not receipt_path.exists():
            raise FileExistsError("Existing signed file preserved; receipt unavailable.")
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        if receipt.get("sha256") != verified["sha256"]:
            raise ValueError("Existing receipt mismatch; preserve files for review.")
        receipt["operation"] = "reuse-existing-local"
        return receipt
    if receipt_path.exists():
        raise FileExistsError("Existing receipt preserved; signed file unavailable.")
    build(folder)
    source = (folder / "Scan3D-Forny.UNSIGNED.plist").read_text(encoding="utf-8")
    validate_workflow(plistlib.loads(source.encode()))
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(NoRedirect(), urllib.request.HTTPCookieProcessor(jar))
    opener.addheaders = [("User-Agent", "Scan3D-ShortcutBuilder/1.0")]
    with opener.open(HOST + "/", timeout=25) as response:
        bounded_read(response)
    token = next((urllib.parse.unquote(c.value) for c in jar if c.name == "XSRF-TOKEN"), None)
    if not token:
        raise ValueError("Anonymous service session unavailable.")
    body = json.dumps({"name": NAME, "data": source}).encode()
    request = urllib.request.Request(HOST + "/sign", body, method="POST", headers={
        "Content-Type": "application/json", "Accept": "application/json",
        "X-XSRF-TOKEN": token, "X-Requested-With": "XMLHttpRequest"})
    with opener.open(request, timeout=35) as response:
        url = storage_url(bounded_read(response).decode("utf-8"))
    with opener.open(url, timeout=25) as response:
        data = bounded_read(response)
    verified = verify_signed_bytes(data)
    receipt = {"name": NAME, "operation": "signed-and-read-back", "url": url,
               "service": "Cherri Playground / HubSign", "sourceSha256": hashlib.sha256(source.encode()).hexdigest(),
               **verified, "scheduledOnPhone": False, "installedOnPhone": False,
               "retentionGuaranteed": False}
    # Do not overwrite different files or a pre-existing receipt.
    with signed.open("xb") as file:
        file.write(data)
    with receipt_path.open("x", encoding="utf-8") as file:
        file.write(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n")
    return receipt


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--approved-service-upload", action="store_true")
    args = parser.parse_args()
    print(json.dumps(sign(args.output, args.approved_service_upload), ensure_ascii=False, indent=2))
