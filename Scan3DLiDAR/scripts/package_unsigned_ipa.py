"""Package the actual unsigned Release iPhone app for subsequent local signing.

No signing credentials, provisioning, installation or third-party uploads.
"""
from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import re
import shutil
import stat
import struct
import zipfile

MAX_BYTES = 256 * 1024 * 1024


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def require_device_binary(path):
    with path.open('rb') as stream:
        header = stream.read(32)
        if len(header) != 32:
            raise ValueError('Missing Mach-O header')
        magic, cpu, subtype, kind, count, size, flags, reserved = struct.unpack('<IiiIIIII', header)
        if magic != 0xfeedfacf or cpu != 0x100000c or kind != 2 or not 0 < count <= 256 or size > 65536:
            raise ValueError('Expected a thin arm64 iPhone executable')
        commands = stream.read(size)
    if len(commands) != size:
        raise ValueError('Truncated load commands')
    offset = 0
    platforms = []
    for _ in range(count):
        if offset + 8 > size:
            raise ValueError('Truncated command')
        cmd, length = struct.unpack_from('<II', commands, offset)
        if length < 8 or length % 4 or offset + length > size:
            raise ValueError('Invalid command length')
        if cmd == 0x32:
            if length < 24:
                raise ValueError('Invalid platform command')
            platforms.append(struct.unpack_from('<I', commands, offset + 8)[0])
        offset += length
    if offset != size or platforms != [2]:
        raise ValueError('Simulator or unknown Mach-O platform; iOS device platform required')


def package(app, output, source_commit):
    app, output = Path(app), Path(output)
    if not re.fullmatch('[a-f0-9]{40}', source_commit):
        raise ValueError('A full source commit is required')
    if app.is_symlink() or not app.is_dir() or app.name != 'Scan3DLiDAR.app':
        raise ValueError('Expected the actual Scan3DLiDAR.app directory')
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if (info.get('CFBundleIdentifier') != 'dk.scan3dstudio.lidar' or info.get('CFBundlePackageType') != 'APPL'
            or info.get('DTPlatformName') != 'iphoneos' or info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']):
        raise ValueError('Unexpected app identity or Simulator build')
    executable = info.get('CFBundleExecutable', '')
    if not re.fullmatch('[A-Za-z0-9_-]+', executable) or not (app / executable).is_file():
        raise ValueError('Missing executable')
    require_device_binary(app / executable)
    files = []
    for path in sorted(app.rglob('*')):
        if path.is_symlink():
            raise ValueError('Linked resources are not accepted')
        if path.is_file():
            if path.suffix.lower() in {'.p12', '.p8', '.pem', '.key', '.mobileprovision'}:
                raise ValueError('Unsigned packages must not contain signing material')
            files.append(path)
    if not files or len(files) > 10000 or sum(p.stat().st_size for p in files) > MAX_BYTES:
        raise ValueError('App resource bounds exceeded')
    output.mkdir(parents=True, exist_ok=False)
    ipa = output / 'Scan3D-unsigned.ipa'
    records = []
    with zipfile.ZipFile(ipa, 'x', compression=zipfile.ZIP_DEFLATED) as archive:
        for path in files:
            name = 'Payload/Scan3DLiDAR.app/' + path.relative_to(app).as_posix()
            item = zipfile.ZipInfo.from_file(path, arcname=name)
            item.compress_type = zipfile.ZIP_DEFLATED
            item.external_attr = (stat.S_IFREG | stat.S_IMODE(path.stat().st_mode)) << 16
            with path.open('rb') as source, archive.open(item, 'w') as target:
                shutil.copyfileobj(source, target, length=1024 * 1024)
            records.append({'path': name, 'bytes': path.stat().st_size, 'sha256': digest(path)})
    with zipfile.ZipFile(ipa) as archive:
        if archive.testzip() is not None or set(archive.namelist()) != {r['path'] for r in records}:
            raise ValueError('IPA structure check failed')
        for record in records:
            h = hashlib.sha256()
            with archive.open(record['path']) as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b''):
                    h.update(block)
            if h.hexdigest() != record['sha256']:
                raise ValueError('IPA readback hash mismatch')
    result = {'schemaVersion': 1, 'sourceCommit': source_commit, 'bundleIdentifier': info['CFBundleIdentifier'],
              'platform': 'iOS-device-arm64', 'configuration': 'Release', 'minimumOS': info.get('MinimumOSVersion'),
              'file': ipa.name, 'bytes': ipa.stat().st_size, 'sha256': digest(ipa), 'installableAsIs': False,
              'signing': 'No Apple provisioning; requires signing with the user\'s own Apple account.',
              'physicalDeviceTested': False, 'files': records}
    (output / 'SCAN3D_PACKAGE.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--source-commit', required=True)
    args = parser.parse_args()
    print(json.dumps(package(args.app, args.output, args.source_commit), indent=2))
