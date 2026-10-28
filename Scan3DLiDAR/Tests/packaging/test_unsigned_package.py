from pathlib import Path
import importlib.util
import json
import os
import plistlib
import struct
import tempfile
import unittest
import zipfile

script = Path(__file__).resolve().parents[2] / 'scripts/package_unsigned_ipa.py'
spec = importlib.util.spec_from_file_location('unsigned_package', script)
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)

class UnsignedPackageTests(unittest.TestCase):
    def setUp(self):
        parent = os.environ.get('SCAN3D_TEST_TMP')
        self.tmp = tempfile.TemporaryDirectory(dir=parent); self.root = Path(self.tmp.name).resolve()
        if parent: self.assertTrue(self.root.is_relative_to(Path(parent).resolve()))
        self.app = self.root / 'Scan3DLiDAR.app'; self.app.mkdir()
        self.info = {'CFBundleIdentifier': 'dk.scan3dstudio.lidar', 'CFBundlePackageType': 'APPL',
                     'DTPlatformName': 'iphoneos', 'CFBundleSupportedPlatforms': ['iPhoneOS'],
                     'CFBundleExecutable': 'Scan3DLiDAR', 'MinimumOSVersion': '17.0',
                     'CFBundleShortVersionString': '0.1.0', 'CFBundleVersion': '1',
                     'UIFileSharingEnabled': True, 'LSSupportsOpeningDocumentsInPlace': True}
        self.write_info(); self.binary()
    def tearDown(self):
        self.tmp.cleanup()
    def write_info(self):
        (self.app / 'Info.plist').write_bytes(plistlib.dumps(self.info))
    def binary(self, platform=2):
        header = struct.pack('<IiiIIIII', 0xfeedfacf, 0x100000c, 0, 2, 1, 24, 0, 0)
        command = struct.pack('<IIIIII', 0x32, 24, platform, 17 << 16, 26 << 16, 0)
        (self.app / 'Scan3DLiDAR').write_bytes(header + command + b'QA fixture, not executable code')
    def build(self):
        return module.package(self.app, self.root / 'out', 'a' * 40)
    def test_roundtrip_and_explicit_unsigned_state(self):
        result = self.build()
        self.assertFalse(result['installableAsIs']); self.assertFalse(result['physicalDeviceTested'])
        self.assertEqual(result['sourceCommit'], 'a' * 40)
        self.assertEqual(result['marketingVersion'], '0.1.0')
        self.assertEqual(result['buildVersion'], '1')
        self.assertIs(result['documentsVisibleInFilesApp'], True)
        self.assertEqual(result['sha256'], module.digest(self.root / 'out/Scan3D-unsigned.ipa'))
        with zipfile.ZipFile(self.root / 'out/Scan3D-unsigned.ipa') as archive:
            self.assertIsNone(archive.testzip())
            self.assertEqual(archive.read('Payload/Scan3DLiDAR.app/Info.plist'), (self.app / 'Info.plist').read_bytes())
    def test_rejects_simulator_even_with_arm64_cpu(self):
        self.binary(platform=7)
        with self.assertRaises(ValueError): self.build()
    def test_rejects_misleading_info_plist(self):
        self.info['DTPlatformName'] = 'iphonesimulator'; self.write_info()
        with self.assertRaises(ValueError): self.build()
    def test_rejects_wrong_bundle_and_executable_path(self):
        for field, value in [('CFBundleIdentifier', 'other.app'), ('CFBundleExecutable', '../Scan3DLiDAR')]:
            original = self.info[field]; self.info[field] = value; self.write_info()
            with self.assertRaises(ValueError): self.build()
            self.info[field] = original
    def test_rejects_missing_or_invalid_app_versions(self):
        for field,value in [('CFBundleShortVersionString',None),
                            ('CFBundleShortVersionString','invalid'),
                            ('CFBundleVersion',None),
                            ('CFBundleVersion','1 beta')]:
            old=self.info.get(field)
            if value is None: self.info.pop(field)
            else: self.info[field]=value
            self.write_info()
            with self.subTest(field=field,value=value), self.assertRaisesRegex(ValueError,'CFBundle'):
                self.build()
            self.info[field]=old
        self.write_info()
    def test_rejects_missing_or_false_files_visibility(self):
        for field in ('UIFileSharingEnabled','LSSupportsOpeningDocumentsInPlace'):
            for value in (None,False):
                with self.subTest(field=field,value=value):
                    old=self.info[field]
                    if value is None: self.info.pop(field)
                    else: self.info[field]=value
                    self.write_info()
                    with self.assertRaisesRegex(ValueError,'Files'):
                        self.build()
                    self.info[field]=old
        self.write_info()
    def test_rejects_truncated_binary(self):
        (self.app / 'Scan3DLiDAR').write_bytes(b'not a device app')
        with self.assertRaises(ValueError): self.build()
    def test_rejects_embedded_signing_material(self):
        (self.app / 'embedded.mobileprovision').write_bytes(b'QA profile fixture')
        with self.assertRaises(ValueError): self.build()
    def test_does_not_overwrite_an_existing_package(self):
        self.build()
        with self.assertRaises(FileExistsError): self.build()
    def test_requires_full_source_provenance(self):
        with self.assertRaises(ValueError): module.package(self.app, self.root / 'out', 'branch-name')

if __name__ == '__main__': unittest.main()
