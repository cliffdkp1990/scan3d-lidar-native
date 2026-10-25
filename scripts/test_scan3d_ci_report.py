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
    def test_error_lines_are_extracted_and_limited(self):
        file=self.root/"scan3d-ui.log"
        file.write_text("normal\nTest Case '-[Scan3DTests.Capture testSomething]' failed (15.0 seconds).\n** TEST FAILED **\n")
        self.assertEqual(len(failures(file)),2)

if __name__=="__main__":unittest.main()
