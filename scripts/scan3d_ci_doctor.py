#!/usr/bin/env python3
"""Read-only, exact-revision Scan3D GitHub Actions doctor.

Classify cancellations, queue delays, failed steps and unsigned artifacts.
Creates JSON and Markdown; NEVER signs, deploys, retries or changes GitHub.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import urllib.error
import urllib.request

SHA_RE = re.compile(r"[0-9a-f]{40}\Z")
REPO_RE = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\Z")
WORKFLOWS = (
    "Scan3D - source tests and iOS Simulator build",
    "Scan3D - portable native Swift core regressions",
    "Scan3D - free Windows install preflight",
)
ARTIFACT = "scan3d-unsigned-iphone"


def gh_json(repo: str, endpoint: str, token: str) -> dict:
    """Never log the token or arbitrary server response bodies."""
    if not REPO_RE.fullmatch(repo) or not endpoint.startswith("/") or ".." in endpoint:
        raise ValueError("Unsafe GitHub repository or API endpoint")
    if not token:
        raise ValueError("GitHub read token required in Actions")
    req = urllib.request.Request(
        "https://api.github.com/repos/" + repo + endpoint,
        headers={"Accept": "application/vnd.github+json",
                 "Authorization": "Bearer " + token,
                 "X-GitHub-Api-Version": "2022-11-28",
                 "User-Agent": "scan3d-readonly-ci-doctor"})
    with urllib.request.urlopen(req, timeout=20) as response:
        data = response.read(2_000_001)
    if len(data) > 2_000_000:
        raise ValueError("GitHub metadata response too large")
    return json.loads(data)


def _job_category(job: dict) -> str:
    if job.get("conclusion") == "failure":
        return "failed"
    if job.get("conclusion") == "cancelled":
        return "cancelled"
    if job.get("conclusion") == "skipped":
        return "skipped"
    if job.get("status") in ("queued", "waiting", "pending"):
        return "queued"
    if job.get("status") == "in_progress":
        return "running"
    if job.get("conclusion") == "success":
        return "passed"
    return "unknown"


def diagnose(run: dict, jobs: list[dict], expected_sha: str, artifacts: list[dict] | None = None) -> dict:
    if not SHA_RE.fullmatch(expected_sha):
        raise ValueError("Full SHA required; abbreviated SHAs are unsafe")
    name = run.get("name", "")
    got = run.get("head_sha")
    exact = got == expected_sha
    status, conclusion = run.get("status"), run.get("conclusion")
    outcomes = [_job_category(j) for j in jobs]
    step_failures = [
        (str(j.get("name", "job"))[:90], str(s.get("name", "step"))[:110])
        for j in jobs for s in j.get("steps", []) if s.get("conclusion") == "failure"
    ][:8]
    if not exact:
        category, action = "STALE_SHA", "Ignorer gammel test: kør på præcis aktuel commit"
    elif status in ("queued", "pending", "waiting"):
        category, action = "RUNNER_QUEUE", "Afvent runner; undersøg GitHub Actions-kapacitet hvis køen bliver lang"
    elif status == "in_progress":
        category, action = "RUNNING", "Kører endnu; afvent konkrete jobtrin"
    elif conclusion == "success" and jobs and all(x == "passed" for x in outcomes):
        category, action = "PASSED", "Kun dette testniveau er grønt; fysisk LiDAR og signering er ikke testet"
    elif conclusion in ("failure", "cancelled") and jobs and not step_failures and all(
            x in ("cancelled", "skipped", "queued") for x in outcomes):
        category, action = "CANCELLED_NO_STEPS", (
            "Ingen dokumenteret Swift-fejl: jobbet blev annulleret før tests; "
            "årsag ukendt. Undersøg macOS-runner, concurrency og fakturering; "
            "gentag højst én gang efter manuel kontrol")
    elif step_failures:
        category, action = "FAILED_STEP", (
            "Læs første fejlede jobtrin i GitHub-loggen; ret kun den konkrete årsag")
    elif conclusion in ("failure", "cancelled"):
        category, action = "FAILED_UNKNOWN", (
            "Fejlet/annulleret uden entydig logårsag; hent logs og artefakter")
    else:
        category, action = "INCOMPLETE", "Ingen gyldig komplet CI-status på denne SHA"
    unsigned = any(str(a.get("name", "")).startswith(ARTIFACT)
                   and a.get("expired") is False for a in (artifacts or []))
    # A successful or existing unsigned IPA never proves installation or LiDAR.
    return {
        "workflow": name, "runId": run.get("id"), "headSHA": got, "matchesExpectedSHA": exact,
        "status": status, "conclusion": conclusion, "category": category, "nextAction": action,
        "jobOutcomes": outcomes, "failedSteps": step_failures,
        "unsignedIpaArtifactFound": unsigned,
        "signed": False, "installedOnIPhone": False, "physicalLiDARVerified": False,
    }


def _report(runs: list[dict], jobs_by_id: dict[str, list[dict]],
            artifacts_by_id: dict[str, list[dict]], sha: str, repo: str) -> dict:
    if not SHA_RE.fullmatch(sha) or not REPO_RE.fullmatch(repo):
        raise ValueError("Invalid repository or SHA")
    current = [r for r in runs if r.get("head_sha") == sha and r.get("name") in WORKFLOWS]
    checks = []
    for name in WORKFLOWS:
        candidates = [r for r in current if r.get("name") == name]
        if not candidates:
            checks.append({"workflow": name, "category": "NOT_RUN",
                           "matchesExpectedSHA": False, "nextAction": "Ingen run på præcis denne commit",
                           "signed": False, "installedOnIPhone": False, "physicalLiDARVerified": False})
            continue
        r = max(candidates, key=lambda x: int(x.get("run_attempt") or 0) * 1_000_000_000_000
                + int(x.get("id") or 0) % 1_000_000_000_000)
        key = str(r["id"])
        checks.append(diagnose(r, jobs_by_id.get(key, []), sha, artifacts_by_id.get(key, [])))
    native, portable, windows = checks
    # Treat queued/cancelled macOS jobs as NOT verified, regardless of a green Linux job.
    return {
        "schemaVersion": 1, "repo": repo, "expectedSHA": sha,
        "checkedAtUTC": datetime.now(timezone.utc).isoformat(),
        "nativeBuildVerified": native["category"] == "PASSED",
        "portableSwiftVerified": portable["category"] == "PASSED",
        "unsignedIpaForExactSHA": native.get("unsignedIpaArtifactFound", False)
                                    if native["category"] == "PASSED" else False,
        "signed": False, "installedOnIPhone": False, "physicalLiDARVerified": False,
        "checks": checks,
    }


def markdown(report: dict) -> str:
    lines = [
        "# Scan3D automatisk diagnosticering",
        "", "**Repository:** " + report["repo"],
        "**Præcis kildecommit:** " + report["expectedSHA"],
        "", "| Kontrol | Diagnose |", "|---|---|",
    ]
    for item in report["checks"]:
        lines.append("| " + item["workflow"] + " | " + item["category"] + " |")
    lines += ["", "## Prioriterede trin"]
    for i, item in enumerate(report["checks"], start=1):
        lines.append(f"{i}. **{item['workflow']}:** {item['nextAction']}")
        for job, step in item.get("failedSteps", []):
            lines.append(f"   - Fejlet trin: {job.replace('|', '/')} / {step.replace('|', '/')}")
    lines += ["", "**Native iOS-build for denne commit:** "
              + ("BESTÅET" if report["nativeBuildVerified"] else "IKKE VERIFICERET"),
              "**Usigneret IPA til denne commit:** "
              + ("FUNDET" if report["unsignedIpaForExactSHA"] else "IKKE VERIFICERET"),
              "", "Fysisk iPhone-LiDAR: ikke verificeret. Apple-signering: ikke verificeret.",
              "Dette er en skrivebeskyttet diagnose, ikke en selvreparerende build eller installer.",
              ""]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--sha", required=True)
    parser.add_argument("--output-dir", default="scan3d-diagnostics")
    parser.add_argument("--fixture", help="Offline JSON: runs, jobs, artifacts")
    args = parser.parse_args()
    if not REPO_RE.fullmatch(args.repo) or not SHA_RE.fullmatch(args.sha):
        parser.error("Full immutable SHA and owner/repo required")
    if args.fixture:
        snapshot = json.loads(Path(args.fixture).read_text(encoding="utf-8"))
        runs = snapshot["runs"]
        jobs = snapshot["jobs"]
        artifacts = snapshot.get("artifacts", {})
    else:
        token = os.environ.get("GITHUB_TOKEN", "")
        try:
            all_runs = gh_json(args.repo, "/actions/runs?per_page=100", token)["workflow_runs"]
            runs = [r for r in all_runs if r.get("head_sha") == args.sha
                    and r.get("name") in WORKFLOWS]
            jobs, artifacts = {}, {}
            for r in runs[:12]:
                key = str(r["id"])
                jobs[key] = gh_json(args.repo, "/actions/runs/" + key + "/jobs?per_page=100",
                                    token).get("jobs", [])
                if r.get("name") == WORKFLOWS[0] and r.get("conclusion") == "success":
                    artifacts[key] = gh_json(args.repo,
                        "/actions/runs/" + key + "/artifacts?per_page=100",
                        token).get("artifacts", [])
        except (urllib.error.URLError, ValueError, KeyError, json.JSONDecodeError) as exc:
            # Never expose token, response bodies or other secrets.
            print("Scan3D doctor: GitHub metadata unavailable. Check Actions read permission.")
            return 2
    report = _report(runs, jobs, artifacts, args.sha, args.repo)
    out = Path(args.output_dir)
    out.mkdir(parents=True, exist_ok=True)
    (out / "scan3d-ci-doctor.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    summary = markdown(report)
    (out / "scan3d-ci-doctor.md").write_text(summary, encoding="utf-8")
    print(summary)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a", encoding="utf-8") as f:
            f.write(summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
