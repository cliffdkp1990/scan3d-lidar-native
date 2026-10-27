#!/usr/bin/env python3
"""Fast regression tests: false green status must be impossible."""
import tempfile
from pathlib import Path
import unittest
from scan3d_ci_report import report, markdown, failures, STEPS

SHA="665922fdbe804757ef1043db89fbdd4901fca1e2"

class AutomatedChecks(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.root=Path(self.temp.name)
        self.passed={key:"success" for key,_,_ in STEPS}
    def tearDown(self):self.temp.cleanup()
    def test_all_green_requires_same_sha(self):
        r=report(SHA,"42",self.passed,self.root)
        self.assertTrue(r["ciPassedForExactCommit"])
        self.assertEqual(r["checkedOutSHA"], SHA)
        self.assertTrue(r["ciPassedForPullRequestHead"])
        self.assertEqual(r["appleSignedInstall"],"not_verified")
    def test_failed_ui_remains_red_even_if_builds_pass(self):
        states=dict(self.passed,ui="failure")
        r=report(SHA,"42",states,self.root)
        self.assertFalse(r["ciPassedForExactCommit"])
        self.assertIn("IKKE bestået",markdown(r))
    def test_skipped_device_remains_red(self):
        self.assertFalse(report(SHA,"42",dict(self.passed,device="skipped"),self.root)["ciPassedForExactCommit"])
    def test_unknown_step_is_never_green(self):
        self.assertFalse(report(SHA,"42",{},self.root)["ciPassedForExactCommit"])
    def test_short_sha_is_rejected(self):
        with self.assertRaises(ValueError):report("665922f","42",self.passed,self.root)
    def test_pull_request_merge_not_mistaken_for_head_commit(self):
        merge_sha="8"*40
        r=report(merge_sha,"42",self.passed,self.root,head_sha=SHA,event="pull_request")
        self.assertTrue(r["ciPassedForExactCommit"])
        self.assertFalse(r["ciPassedForPullRequestHead"])
        self.assertEqual(r["checkedOutSHA"],merge_sha)
        self.assertEqual(r["pullRequestHeadSHA"],SHA)
        self.assertIn("ikke separat bevis",markdown(r))
    def test_pull_request_requires_head_sha(self):
        with self.assertRaises(ValueError):
            report(SHA,"42",self.passed,self.root,event="pull_request")
    def test_normal_push_rejects_sha_mismatch(self):
        with self.assertRaises(ValueError):
            report(SHA,"42",self.passed,self.root,head_sha="8"*40,event="push")
    def test_unsigned_ipa_is_only_packaged_after_all_native_checks(self):
        flow=(Path(__file__).resolve().parent.parent /
              ".github/workflows/scan3d-lidar.yml").read_text(encoding="utf-8")
        section=flow.split("      - name: Package unsigned IPA for local iPhone testing",1)[1]
        section=section.split("      - name: Generate SHA-bound CI report",1)[0]
        self.assertIn("github.event_name == 'pull_request'",section)
        for gate in ("fast_preflight","source_tests","debug_build",
                     "native_ui","release_build","device_build"):
            self.assertIn("steps."+gate+".outcome == 'success'",section)
        self.assertIn("Scan3D-unsigned-local-test.ipa",section)
        self.assertIn("Scan3D-unsigned-local-test.ipa.sha256",section)
        self.assertIn("PR_HEAD_SHA",section)
        self.assertIn("ACTUAL_CHECKOUT_SHA",section)
        self.assertIn('test ! -e "$APP/embedded.mobileprovision"',section)
        self.assertIn("retention-days: 7",section)
        self.assertNotIn("altool",section)
        self.assertNotIn("notarytool",section)
    def test_error_lines_are_extracted_and_limited(self):
        file=self.root/"scan3d-ui.log"
        file.write_text("normal\nTest Case '-[Scan3DTests.Capture testSomething]' failed (15.0 seconds).\n** TEST FAILED **\n")
        self.assertEqual(len(failures(file)),2)
    def test_stack_update_preserves_head_checkout_and_both_iphone_packages(self):
        flow=(Path(__file__).resolve().parent.parent /
              ".github/workflows/scan3d-lidar.yml").read_text(encoding="utf-8")
        self.assertIn("SCAN3D_SOURCE_COMMIT: ${{ github.event.pull_request.head.sha || github.sha }}",flow)
        self.assertIn("ref: ${{ env.SCAN3D_SOURCE_COMMIT }}",flow)
        self.assertIn("python3 -m unittest discover -s Tests/packaging -v",flow)
        self.assertIn('test "$(git rev-parse HEAD)" = "$SCAN3D_SOURCE_COMMIT"',flow)
        self.assertIn("python3 Scan3DLiDAR/scripts/package_unsigned_ipa.py",flow)
        self.assertIn('name: scan3d-unsigned-iphone\n',flow)
        self.assertIn("name: scan3d-unsigned-ipa-${{ github.event.pull_request.head.sha }}",flow)
        ordered=["Run native camera and model-viewer UI tests",
                 "Compile Release without test fixture activation",
                 "Compile unsigned iOS device app",
                 "Package unsigned iPhone app for local signing",
                 "Save unsigned iPhone package",
                 "Package unsigned IPA for local iPhone testing",
                 "Upload unsigned IPA for local signing only",
                 "Generate SHA-bound CI report"]
        positions=[flow.index("      - name: "+name) for name in ordered]
        self.assertEqual(positions,sorted(positions))

if __name__=="__main__":unittest.main()
