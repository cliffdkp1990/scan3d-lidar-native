"""Unit tests: never turn real Swift/XCTest failures into auto-retries."""
import unittest
from unittest.mock import patch
import json
from pathlib import Path
from scan3d_doctor import classify, diagnose, redacted, maintain_issue

REPO="cliffdkp1990/scan3d-lidar-native"
SHA="a"*40
PR={"number":4,"head":{"ref":"ci/repair","sha":SHA,"repo":{"full_name":REPO}}}
RUN={"repository":{"full_name":REPO},"name":"Scan3D - source tests and iOS Simulator build",
     "head_sha":SHA,"head_branch":"ci/repair",
     "status":"completed","conclusion":"failure","run_attempt":1,
     "id":42,"html_url":"https://github.com/cliffdkp1990/scan3d-lidar-native/actions/runs/42"}

def job(step):
    return [{"conclusion":"failure","steps":[{"conclusion":"failure","name":step}]}]

class DoctorTests(unittest.TestCase):
    def test_one_retry_of_transient_checkout_failure(self):
        r=diagnose(RUN,job("Run actions/checkout@v4"),[PR],"HTTP 503 Service Unavailable")
        self.assertTrue(r["retryOnceAllowed"])
    def test_never_retry_ui_errors(self):
        r=diagnose(RUN,job("Run native camera and model-viewer UI tests"),[PR],
                   "Test Case failed; HTTP 503")
        self.assertEqual(r["category"],"ui_test")
        self.assertFalse(r["retryOnceAllowed"])
    def test_never_retry_compiler_errors(self):
        r=diagnose(RUN,job("Compile unsigned iOS device app"),[PR],"error: undeclared name")
        self.assertFalse(r["retryOnceAllowed"])
    def test_stale_sha_not_retried(self):
        r=diagnose(dict(RUN,head_sha="b"*40),job("Set up job"),[PR],"HTTP 503")
        self.assertFalse(r["retryOnceAllowed"])
    def test_second_attempt_not_retried(self):
        r=diagnose(dict(RUN,run_attempt=2),job("Set up job"),[PR],"HTTP 503")
        self.assertFalse(r["retryOnceAllowed"])
    def test_other_repo_not_retried(self):
        r=diagnose(dict(RUN,repository={"full_name":"other/repo"}),
                   job("Set up job"),[PR],"HTTP 503")
        self.assertFalse(r["retryOnceAllowed"])
    def test_no_rerun_without_failure(self):
        r=diagnose(dict(RUN,conclusion="success"),[],[PR],"")
        self.assertFalse(r["retryOnceAllowed"])
    def test_missing_pr_not_retried(self):
        r=diagnose(RUN,job("Set up job"),[],"HTTP 503")
        self.assertFalse(r["retryOnceAllowed"])
    def test_device_is_not_marked_signed(self):
        r=diagnose(RUN,job("Run native camera and model-viewer UI tests"),[PR],"error: xctest")
        self.assertEqual(r["signedBuild"],"not_verified")
        self.assertEqual(r["physicalLiDAR"],"not_verified")
    def test_other_workflow_never_retried(self):
        r=diagnose(dict(RUN,name="Unrelated Workflow"),job("Set up job"),[PR],"HTTP 503")
        self.assertFalse(r["retryOnceAllowed"])
    def test_compiler_error_not_misclassified_when_xctest_in_log(self):
        kind,_=classify(["Compile unsigned iOS device app"],
                        "xctest runner mentioned earlier\nerror: Swift compiler stopped")
        self.assertEqual(kind,"code_or_build")
    def test_existing_issue_keeps_manual_notes(self):
        data=diagnose(RUN,job("Run native camera and model-viewer UI tests"),[PR],
                      "Test Case 'viewer' failed")
        calls=[]
        def fake_gh(*args):
            calls.append(args)
            if args[:2]==("issue","list"):
                return json.dumps([{"number":19,"title":"Scan3D CI Doctor: PR #4 needs repair",
                                    "body":"My manual investigation must be preserved"}])
            if args[:2]==("issue","view"):
                return json.dumps({"comments":[]})
            if args[:2]==("issue","comment"):
                return "comment published"
            raise AssertionError(args)
        with patch("scan3d_doctor.gh",side_effect=fake_gh):
            result=maintain_issue(data)
        self.assertIn("Appended",result)
        self.assertTrue(any(a[:2]==("issue","comment") for a in calls))
        self.assertFalse(any(a[:2]==("issue","edit") for a in calls))
    def test_issues_do_not_duplicate_a_recorded_run(self):
        data=diagnose(RUN,job("Run native camera and model-viewer UI tests"),[PR],
                      "Test Case 'viewer' failed")
        calls=[]
        def fake_gh(*args):
            calls.append(args)
            if args[:2]==("issue","list"):
                return json.dumps([{"number":19,"title":"Scan3D CI Doctor: PR #4 needs repair",
                                    "body":"Manual notes"}])
            if args[:2]==("issue","view"):
                return json.dumps({"comments":[{"body":"<!-- scan3d-doctor run=42 -->"}]})
            raise AssertionError(args)
        with patch("scan3d_doctor.gh",side_effect=fake_gh):
            result=maintain_issue(data)
        self.assertIn("already documented",result)
        self.assertFalse(any(a[:2]==("issue","comment") for a in calls))
    def test_main_branch_checks_cover_doctor_scripts_and_workflow(self):
        workflow = (Path(__file__).resolve().parent.parent
                    / ".github/workflows/scan3d-lidar.yml").read_text(encoding="utf-8")
        push = workflow.split("\\n  push:\\n", 1)[1].split("\\n  pull_request:", 1)[0]
        self.assertIn("'scripts/**'", push)
        self.assertIn("'.github/workflows/scan3d-doctor.yml'", push)
        self.assertIn("'.github/workflows/scan3d-lidar.yml'", push)
    def test_secret_redaction(self):
        self.assertNotIn("ghp_ABCdef0123456789",redacted("ghp_ABCdef0123456789"))

if __name__=="__main__":
    unittest.main()
