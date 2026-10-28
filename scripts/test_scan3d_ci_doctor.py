"""Offline deterministic safety tests for the read-only Scan3D CI doctor."""
import unittest
from scan3d_ci_doctor import WORKFLOWS, _report, diagnose, markdown

SHA = "a" * 40
OTHER_SHA = "b" * 40
REPO = "cliffdkp1990/scan3d-lidar-native"


def run(name=WORKFLOWS[0], status="completed", conclusion="success", sha=SHA, rid=41):
    return {"id": rid, "name": name, "head_sha": sha, "status": status,
            "conclusion": conclusion, "run_attempt": 1}


def job(status="completed", conclusion="success", steps=None):
    return {"name": "iOS build", "status": status, "conclusion": conclusion,
            "steps": [] if steps is None else steps}


class DoctorTests(unittest.TestCase):
    def test_actual_green_run_only_confirms_that_level(self):
        item = diagnose(run(), [job()], SHA, [{"name": "scan3d-unsigned-iphone",
                                                "expired": False}])
        self.assertEqual(item["category"], "PASSED")
        self.assertTrue(item["unsignedIpaArtifactFound"])
        self.assertFalse(item["signed"])
        self.assertFalse(item["installedOnIPhone"])
        self.assertFalse(item["physicalLiDARVerified"])

    def test_github_failure_with_cancelled_jobs_is_not_swift_error(self):
        item = diagnose(run(conclusion="failure"),
                        [job(conclusion="cancelled"), job(conclusion="skipped")], SHA)
        self.assertEqual(item["category"], "CANCELLED_NO_STEPS")
        self.assertIn("Ingen dokumenteret Swift-fejl", item["nextAction"])
        self.assertNotEqual(item["category"], "PASSED")

    def test_queue_and_running_never_green(self):
        for status in ("queued", "in_progress"):
            item = diagnose(run(status=status, conclusion=None), [job(status=status, conclusion=None)], SHA)
            self.assertNotEqual(item["category"], "PASSED")

    def test_first_failed_step_retained(self):
        item = diagnose(run(conclusion="failure"),
                        [job(conclusion="failure", steps=[
                            {"name": "Swift compile", "conclusion": "failure"},
                            {"name": "Upload evidence", "conclusion": "skipped"}])], SHA)
        self.assertEqual(item["category"], "FAILED_STEP")
        self.assertEqual(item["failedSteps"], [("iOS build", "Swift compile")])

    def test_no_jobs_does_not_become_success(self):
        self.assertNotEqual(diagnose(run(), [], SHA)["category"], "PASSED")

    def test_mismatch_cannot_be_green(self):
        self.assertEqual(diagnose(run(sha=OTHER_SHA), [job()], SHA)["category"], "STALE_SHA")

    def test_older_ipa_cannot_match_current_sha(self):
        report = _report([run(sha=OTHER_SHA)], {"41": [job()]},
                         {"41": [{"name": "scan3d-unsigned-iphone", "expired": False}]}, SHA, REPO)
        self.assertFalse(report["nativeBuildVerified"])
        self.assertFalse(report["unsignedIpaForExactSHA"])
        self.assertTrue(all(x["category"] == "NOT_RUN" for x in report["checks"]))

    def test_portable_green_cannot_replace_native(self):
        portable = run(name=WORKFLOWS[1], rid=50)
        report = _report([portable], {"50": [job()]}, {}, SHA, REPO)
        self.assertTrue(report["portableSwiftVerified"])
        self.assertFalse(report["nativeBuildVerified"])
        self.assertFalse(report["unsignedIpaForExactSHA"])
        self.assertIn("IKKE VERIFICERET", markdown(report))

    def test_native_cancelled_and_portable_pass_is_blocked(self):
        native = run(conclusion="failure")
        portable = run(name=WORKFLOWS[1], rid=50)
        report = _report([native, portable],
                         {"41": [job(conclusion="cancelled")], "50": [job()]},
                         {}, SHA, REPO)
        self.assertFalse(report["nativeBuildVerified"])
        self.assertTrue(report["portableSwiftVerified"])
        self.assertEqual(report["checks"][0]["category"], "CANCELLED_NO_STEPS")

    def test_bad_sha_refused(self):
        with self.assertRaises(ValueError):
            diagnose(run(), [], "abc")


if __name__ == "__main__":
    unittest.main()
