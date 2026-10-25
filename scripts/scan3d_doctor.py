#!/usr/bin/env python3
"""Scan3D Doctor. Read-only unless --apply. Never edits code, merges or deploys."""
import argparse
import datetime as dt
import json
import os
import pathlib
import re
import subprocess
import sys

REPO="cliffdkp1990/scan3d-lidar-native"
WORKFLOW="Scan3D - source tests and iOS Simulator build"
TRANSIENT=re.compile(r"HTTP\s+(?:502|503|504)\b|connection reset by peer|"
                     r"failed to download action|the runner has received a shutdown signal",re.I)
ISSUE_MARKER="scan3d-doctor run="
SECRET=re.compile(r"gh[pousr]_[A-Za-z0-9_]{12,}|github_pat_[A-Za-z0-9_]{12,}",re.I)

def gh(*args):
    p=subprocess.run(["gh",*args],capture_output=True,text=True,timeout=90)
    if p.returncode:
        raise RuntimeError("GitHub CLI command failed. Check gh auth status and token permissions.")
    return p.stdout

def api(path):
    return json.loads(gh("api",path))

def redacted(s):
    s=SECRET.sub("[redacted]",s)
    s=re.sub(r"/Users/runner/work/\S+","<runner-path>",s)
    return " ".join(s.replace("|","/").replace("\r","").split())[:350]

def classify(steps,log):
    names=" ".join(steps).lower()
    errors=[redacted(x) for x in log.splitlines()
            if re.search(r"error:|Test Case .* failed|TEST FAILED",x,re.I)]
    first=errors[0] if errors else redacted(next((x for x in log.splitlines()
                                                     if TRANSIENT.search(x)),"No precise log cause identified."))
    if "native camera" in names or "ui test" in names or "xctest" in log.lower():
        return "ui_test",first
    if any(s in names for s in ("source","compile","release","preflight")):
        return "code_or_build",first
    if "xcode" in names or "simulator" in names:
        return "toolchain",first
    if re.search(r"permission|not authorized|resource not accessible",log,re.I):
        return "permissions",first
    if steps and all("set up job" in x.lower() or "checkout" in x.lower() for x in steps) and TRANSIENT.search(log):
        return "transient_runner",first
    return "unknown",first

def diagnose(run,jobs,prs,log):
    failed=[s.get("name","?") for job in jobs if job.get("conclusion")=="failure"
            for s in job.get("steps",[]) if s.get("conclusion")=="failure"]
    kind,error=classify(failed,log)
    matching=[p for p in prs if p.get("head",{}).get("ref")==run.get("head_branch")
              and p.get("head",{}).get("repo",{}).get("full_name")==REPO]
    pr=next((p for p in matching if p.get("head",{}).get("sha")==run.get("head_sha")),
            matching[0] if matching else None)
    current=bool(pr and pr.get("head",{}).get("sha")==run.get("head_sha"))
    valid=run.get("repository",{}).get("full_name")==REPO
    retry=(valid and run.get("status")=="completed"
           and run.get("conclusion")=="failure" and run.get("run_attempt")==1
           and current and kind=="transient_runner")
    return {"schemaVersion":1,"checkedAtUTC":dt.datetime.now(dt.timezone.utc).isoformat(),
            "repository":REPO,"runId":run.get("id"),"url":run.get("html_url"),
            "headSHA":run.get("head_sha"),"branch":run.get("head_branch"),
            "prNumber":pr.get("number") if pr else None,"headCurrent":current,
            "runAttempt":run.get("run_attempt"),"conclusion":run.get("conclusion"),
            "category":kind,"firstError":error,"failedSteps":failed,
            "retryOnceAllowed":retry,"signedBuild":"not_verified",
            "physicalLiDAR":"not_verified"}

def maintain_issue(data):
    if not data["prNumber"] or not data["headCurrent"]:
        return "No current PR; no issue change."
    title="Scan3D CI Doctor: PR #{} needs repair".format(data["prNumber"])
    issues=json.loads(gh("issue","list","--repo",REPO,"--state","open",
                        "--limit","100","--json","number,title,body"))
    issue=next((x for x in issues if x.get("title")==title),None)
    if issue and (ISSUE_MARKER+str(data["runId"])) in issue.get("body",""):
        return "Issue already contains this run."
    body="\n".join(["Automated diagnostic. Not proof of a fixed build.",
                    "PR: #{}".format(data["prNumber"]),
                    "Branch: "+str(data["branch"]),
                    "Commit SHA: "+str(data["headSHA"]),
                    "Run: "+str(data["url"]),
                    "First failure: "+str(data["firstError"]),
                    "Category: "+str(data["category"]),
                    "Next: fix the actual source/RealityKit/test fault and rerun native CI.",
                    "No automatic merge, deployment or physical iPhone test.",
                    "<!-- "+ISSUE_MARKER+str(data["runId"])+" -->"])
    if issue:
        gh("issue","edit",str(issue["number"]),"--repo",REPO,"--body",body)
        return "Updated existing repair issue #{}".format(issue["number"])
    gh("issue","create","--repo",REPO,"--title",title,"--body",body)
    return "Created repair issue."

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--run-id",default="latest")
    p.add_argument("--repo",default=os.environ.get("GITHUB_REPOSITORY",REPO))
    p.add_argument("--apply",action="store_true")
    p.add_argument("--output-dir",default=".")
    a=p.parse_args()
    if a.repo!=REPO:
        p.error("This script only operates on the verified Scan3D repository")
    try:
        if a.run_id=="latest":
            runs=api("repos/{}/actions/runs?per_page=50".format(REPO))["workflow_runs"]
            found=next((x for x in runs if x.get("name")==WORKFLOW
                        and x.get("status")=="completed" and x.get("conclusion")=="failure"),None)
            if found is None:
                raise RuntimeError("No recently failed completed Scan3D workflow run")
            rid=int(found["id"])
        else:
            rid=int(a.run_id)
        run=api("repos/{}/actions/runs/{}".format(REPO,rid))
        if run.get("repository",{}).get("full_name")!=REPO:
            raise RuntimeError("Unknown repository for requested run")
        jobs=api("repos/{}/actions/runs/{}/jobs?per_page=100".format(REPO,rid)).get("jobs",[])
        prs=api("repos/{}/pulls?state=open&per_page=100".format(REPO))
        try:
            log=gh("run","view",str(rid),"--repo",REPO,"--log-failed")[-400000:]
        except RuntimeError:
            log=""
        data=diagnose(run,jobs,prs,log)
        dest=pathlib.Path(a.output_dir)
        dest.mkdir(parents=True,exist_ok=True)
        (dest/"scan3d-doctor-status.json").write_text(
            json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
        print(json.dumps(data,ensure_ascii=False,indent=2))
        if a.apply and data["retryOnceAllowed"]:
            gh("run","rerun",str(rid),"--repo",REPO,"--failed")
            print("One bounded retry started; not yet verified as successful.")
        elif a.apply and data["conclusion"]=="failure" and data["category"]!="transient_runner":
            print(maintain_issue(data))
        else:
            print("Read-only diagnosis. Nothing safely retried.")
        return 0
    except (ValueError,RuntimeError,KeyError,OSError,subprocess.TimeoutExpired) as exc:
        print("ERROR: "+redacted(str(exc)),file=sys.stderr)
        return 2

if __name__=="__main__":
    sys.exit(main())
