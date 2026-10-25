#!/usr/bin/env python3
"""Produce a commit-bound CI report without concealing failing or skipped tests."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re

STEPS = [
    ("source", "Source / video tests", "scan3d-source-tests.log"),
    ("debug", "Debug Simulator build", "scan3d-build.log"),
    ("ui", "Native UI tests", "scan3d-ui.log"),
    ("release", "Release Simulator build", "scan3d-release.log"),
    ("device", "Unsigned iPhone-target build", "scan3d-device.log"),
]
STATES = {"success", "failure", "skipped", "cancelled", "unknown"}
ERROR = re.compile(r"error:|Fatal error:|TEST FAILED|Test Case .+ failed|XCTAssert\w* failed|FAIL:",re.I)

def failures(path: Path, max_entries: int = 3) -> list[str]:
    if not path.is_file():
        return []
    matches=[]
    for row in path.read_text(errors="replace",encoding="utf-8").splitlines():
        if not ERROR.search(row):
            continue
        row = re.sub(r"^\d{4}-\d\d-\d\dT[^ ]+Z\s+", "", row)
        row = re.sub(r"/Users/runner/work/[^\s:]+", "<workspace>", row)
        matches.append(row[:250])
        if len(matches) >= max_entries:
            break
    return matches

def report(sha: str, run: str, statuses: dict[str,str], logs: Path,
           head_sha: str | None = None, event: str = "unknown") -> dict:
    # On pull_request, actions/checkout normally builds refs/pull/N/merge,
    # NOT the PR branch head. Both must be recorded to avoid a false assertion.
    if not re.fullmatch(r"[0-9a-f]{40}",sha):
        raise ValueError("Exact 40-character checked-out SHA required")
    if head_sha is not None and not re.fullmatch(r"[0-9a-f]{40}",head_sha):
        raise ValueError("Exact 40-character source head SHA required")
    if event == "pull_request" and head_sha is None:
        raise ValueError("A pull_request report requires its actual head SHA")
    if event not in {"unknown","pull_request","push","workflow_dispatch"}:
        raise ValueError("Unrecognized GitHub event")
    if event != "pull_request" and head_sha is not None and head_sha != sha:
        raise ValueError("Non-PR source SHA disagrees with checked-out SHA")
    steps=[]
    for key,title,filename in STEPS:
        status=statuses.get(key,"unknown")
        if status not in STATES:
            raise ValueError(f"Invalid status for {key}: {status}")
        steps.append({"id":key,"title":title,"status":status,
                      "errors":failures(logs / filename) if status=="failure" else []})
    all_passed = all(x["status"]=="success" for x in steps)
    return {"schemaVersion":2,"commitSHA":sha,"checkedOutSHA":sha,
            "pullRequestHeadSHA":head_sha if event=="pull_request" else None,
            "eventName":event,"runId":str(run),
            "checkedAtUTC":datetime.now(timezone.utc).isoformat(),
            "ciPassedForExactCommit":all_passed,
            "ciPassedForPullRequestHead":all_passed and head_sha==sha if event=="pull_request" else all_passed,
            "physicalIPhoneTest":"not_verified","appleSignedInstall":"not_verified",
            "steps":steps}

def markdown(data: dict) -> str:
    rows=[f'## Scan3D CI · testet checkout `{data["checkedOutSHA"][:10]}`',
          "",f'Run: `{data["runId"]}` · Checket ud `{data["checkedOutSHA"]}`',
          "", "| Testniveau | Faktisk resultat |", "|---|---|"]
    for item in data["steps"]:
        rows.append(f'| {item["title"]} | **{item["status"]}** |')
    if data["eventName"] == "pull_request":
        rows += ["",f'PR-head: `{data["pullRequestHeadSHA"]}`',
                 "Der testes en GitHub checkout (typisk PR-merge). "
                 "Grøn CI er ikke separat bevis for et standalone build af PR-head."]
    rows += ["","**Samlet status:** "+("Bestået for faktisk checket ud kode" if data["ciPassedForExactCommit"] else "IKKE bestået for faktisk checket ud kode"),
             "","Fysisk LiDAR/iPhone-test: ikke verificeret. Signering: ikke verificeret.",
             "","### Første konkrete fejl pr. fejlet trin"]
    for item in data["steps"]:
        if item["status"]=="failure":
            rows.append(f'- **{item["title"]}**')
            rows += ["  - `"+err.replace("`","'").replace("|","/")+"`" for err in item["errors"]]
            if not item["errors"]:
                rows.append("  - Ingen klar fejl i tekstloggen. Gennemgå xcresult og artefakter.")
    return "\n".join(rows)+"\n"

def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sha",required=True,help="git rev-parse HEAD after checkout")
    parser.add_argument("--head-sha",help="PR branch head SHA, not the generated merge SHA")
    parser.add_argument("--event",default="unknown",choices=["unknown","pull_request","push","workflow_dispatch"])
    parser.add_argument("--run-id",required=True)
    parser.add_argument("--log-directory",required=True)
    parser.add_argument("--output",required=True)
    for key,_,_ in STEPS:
        parser.add_argument("--"+key,choices=sorted(STATES),default="unknown")
    args=parser.parse_args()
    d=report(args.sha,args.run_id,{key:getattr(args,key) for key,_,_ in STEPS},
             Path(args.log_directory),head_sha=args.head_sha,event=args.event)
    output=Path(args.output)
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(d,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
    summary=markdown(d)
    print(summary)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a",encoding="utf-8") as handle:
            handle.write(summary)
    # Do not override actual CI failures with an error in the reporter.
    return 0

if __name__=="__main__":
    raise SystemExit(main())
