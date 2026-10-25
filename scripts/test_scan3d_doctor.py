"""Unit tests: never turn real Swift/XCTest failures into auto-retries."""
import unittest
from scan3d_doctor import classify, diagnose, redacted

REPO="cliffdkp1990/scan3d-lidar-native"
SHA="a"*40
PR={"number":4,"head":{"ref":"ci/repair","sha":SHA,"repo":{"full_name":REPO}}}
RUN={"repository":{"full_name":REPO},"head_sha":SHA,"head_branch":"ci/repair",
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
    def test_secret_redaction(self):
        self.assertNotIn("ghp_ABCdef0123456789",redacted("ghp_ABCdef0123456789"))

if __name__=="__main__":
    unittest.main()
