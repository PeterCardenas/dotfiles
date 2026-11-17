#!/usr/bin/env python3
"""Wait for one PR head commit's GitHub checks with a bounded, deterministic loop.

Exit codes:
  0 all checks passed   1 a check failed   2 usage/API error
  3 PR head moved       4 no checks registered   8 still pending at budget
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from typing import Literal

Bucket = Literal["pass", "fail", "pending"]

PASS_CONCLUSIONS = {"success", "skipped", "neutral"}
EXIT_PASS, EXIT_FAIL, EXIT_ERROR, EXIT_HEAD_MOVED, EXIT_NO_CHECKS, EXIT_PENDING = (
    0,
    1,
    2,
    3,
    4,
    8,
)


@dataclass(frozen=True)
class Check:
    name: str
    bucket: Bucket
    detail: str
    url: str


def gh(*args: str) -> str:
    result = subprocess.run(["gh", *args], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"gh {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout


def classify_check_runs(runs: list[dict[str, object]]) -> list[Check]:
    # Reruns create new check runs with the same name; only the newest one counts.
    latest: dict[str, dict[str, object]] = {}
    for run in runs:
        name = str(run["name"])
        if name not in latest or int(str(run["id"])) > int(str(latest[name]["id"])):
            latest[name] = run
    checks = []
    for name, run in sorted(latest.items()):
        status, conclusion = str(run["status"]), str(run.get("conclusion") or "")
        if status != "completed":
            bucket: Bucket = "pending"
        elif conclusion in PASS_CONCLUSIONS:
            bucket = "pass"
        else:
            bucket = "fail"
        checks.append(
            Check(name, bucket, conclusion or status, str(run.get("html_url") or ""))
        )
    return checks


def classify_statuses(statuses: list[dict[str, object]]) -> list[Check]:
    bucket_by_state: dict[str, Bucket] = {"success": "pass", "pending": "pending"}
    return [
        Check(
            str(status["context"]),
            bucket_by_state.get(str(status["state"]), "fail"),
            str(status["state"]),
            str(status.get("target_url") or ""),
        )
        for status in statuses
    ]


def fetch_checks(repo: str, sha: str) -> list[Check]:
    # REST only: the GraphQL quota is what killed `gh pr checks --watch` in past sessions.
    run_lines = gh(
        "api",
        "--paginate",
        f"repos/{repo}/commits/{sha}/check-runs?per_page=100",
        "--jq",
        ".check_runs[] | {id,name,status,conclusion,html_url}",
    )
    runs = [json.loads(line) for line in run_lines.splitlines() if line.strip()]
    statuses = json.loads(
        gh("api", f"repos/{repo}/commits/{sha}/status", "--jq", ".statuses")
    )
    return classify_check_runs(runs) + classify_statuses(statuses)


def print_unresolved_threads(repo: str, number: int) -> None:
    owner, name = repo.split("/")
    query = (
        "query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name)"
        "{pullRequest(number:$number){reviewThreads(first:100){nodes{isResolved isOutdated"
        " comments(first:1){nodes{author{login} url body}}}}}}}"
    )
    threads = json.loads(
        gh(
            "api",
            "graphql",
            "-f",
            f"query={query}",
            "-f",
            f"owner={owner}",
            "-f",
            f"name={name}",
            "-F",
            f"number={number}",
            "--jq",
            ".data.repository.pullRequest.reviewThreads.nodes",
        )
    )
    unresolved = [t for t in threads if not t["isResolved"] and not t["isOutdated"]]
    print(f"UNRESOLVED_THREADS: {len(unresolved)}")
    for thread in unresolved:
        comment = thread["comments"]["nodes"][0]
        first_line = (
            comment["body"].strip().splitlines()[0][:120]
            if comment["body"].strip()
            else ""
        )
        print(f"  {comment['author']['login']}: {first_line} {comment['url']}")


def report(checks: list[Check]) -> None:
    for check in checks:
        if check.bucket != "pass":
            print(
                f"  {check.bucket.upper():8} {check.name} ({check.detail}) {check.url}"
            )


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "pr",
        nargs="?",
        default="",
        help="PR number/URL/branch; default: current branch",
    )
    parser.add_argument(
        "--budget", type=int, default=540, help="max seconds to wait (default 540)"
    )
    parser.add_argument(
        "--interval", type=int, default=30, help="poll seconds (default 30)"
    )
    parser.add_argument(
        "--settle", type=int, default=120, help="seconds to wait for checks to register"
    )
    parser.add_argument(
        "--no-fail-fast",
        action="store_true",
        help="wait for all checks even after a failure",
    )
    args = parser.parse_args()

    try:
        pr = json.loads(
            gh(
                "pr",
                "view",
                *([args.pr] if args.pr else []),
                "--json",
                "number,url,headRefOid",
            )
        )
        match = re.match(r"https://github\.com/([^/]+/[^/]+)/pull/\d+", pr["url"])
        if not match:
            raise RuntimeError(f"cannot parse repo from {pr['url']}")
        repo, number, sha = match.group(1), int(pr["number"]), str(pr["headRefOid"])
        print(f"PR: {pr['url']} SHA: {sha[:12]}")

        start = time.monotonic()
        while True:
            elapsed = time.monotonic() - start
            current_sha = gh(
                "api", f"repos/{repo}/pulls/{number}", "--jq", ".head.sha"
            ).strip()
            if current_sha != sha:
                print(
                    f"RESULT: HEAD_MOVED {sha[:12]} -> {current_sha[:12]}; rerun to watch the new head"
                )
                return EXIT_HEAD_MOVED
            checks = fetch_checks(repo, sha)
            buckets = {check.bucket for check in checks}
            if not checks and elapsed >= args.settle:
                print(f"RESULT: NO_CHECKS registered after {int(elapsed)}s")
                return EXIT_NO_CHECKS
            if (
                checks
                and "fail" in buckets
                and (not args.no_fail_fast or "pending" not in buckets)
            ):
                report(checks)
                print(f"RESULT: FAIL after {int(elapsed)}s")
                return EXIT_FAIL
            if checks and buckets == {"pass"}:
                print(f"RESULT: PASS {len(checks)} checks after {int(elapsed)}s")
                print_unresolved_threads(repo, number)
                return EXIT_PASS
            if elapsed + args.interval > args.budget:
                report(checks)
                print(f"RESULT: PENDING after {int(elapsed)}s; rerun the same command")
                return EXIT_PENDING
            time.sleep(args.interval)
    except (RuntimeError, json.JSONDecodeError, KeyError) as error:
        print(f"RESULT: ERROR {error}", file=sys.stderr)
        return EXIT_ERROR


if __name__ == "__main__":
    sys.exit(main())
