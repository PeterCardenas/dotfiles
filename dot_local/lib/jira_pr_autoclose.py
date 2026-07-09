from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from collections.abc import Sequence

from connector_delegate import choose_output_mode, run_delegate


JIRA_BASE_URL = "https://appliedintuition.atlassian.net/browse"
DEFAULT_JIRA_TOOLS = ("mcp__claude_ai_Atlassian__*",)
ISSUE_KEY_RE = re.compile(r"^[A-Z][A-Z0-9]+-\d+$")
AUTOCLOSE_RE_TEMPLATE = (
    r"(?im)\b(fix(?:e[sd])?|close[sd]?|resolve[sd]?)\b"
    r"[^\n]*(\b{issue_key}\b|/browse/{issue_key}\b)"
)


def normalize_issue_key(raw_issue_key: str) -> str:
    issue_key = raw_issue_key.strip().upper()
    if ISSUE_KEY_RE.fullmatch(issue_key) is None:
        raise ValueError(f"invalid Jira issue key: {raw_issue_key!r}")
    return issue_key


def jira_issue_url(issue_key: str) -> str:
    return f"{JIRA_BASE_URL}/{issue_key}"


def autoclose_line(issue_key: str) -> str:
    return f"Fixes [{issue_key}]({jira_issue_url(issue_key)})."


def body_has_autoclose_line(body: str, issue_key: str) -> bool:
    pattern = AUTOCLOSE_RE_TEMPLATE.format(issue_key=re.escape(issue_key))
    return re.search(pattern, body) is not None


def ensure_pr_body_autoclose(body: str, issue_key: str) -> str:
    if body_has_autoclose_line(body, issue_key):
        return body

    line = autoclose_line(issue_key)
    if not body.strip():
        return line + "\n"

    lines = body.splitlines()
    for index, body_line in enumerate(lines):
        if body_line.strip().lower() != "## summary":
            continue

        insert_at = index + 1
        while insert_at < len(lines) and lines[insert_at].strip() == "":
            insert_at += 1
        updated_lines = lines[:insert_at] + [line, ""] + lines[insert_at:]
        return "\n".join(updated_lines).rstrip() + "\n"

    return line + "\n\n" + body.rstrip() + "\n"


def build_jira_prompt(
    *,
    issue_key: str,
    pr_url: str,
    pr_title: str,
    comment: str,
) -> str:
    issue_url = jira_issue_url(issue_key)
    return (
        "You are a Jira write connector delegate for an explicitly requested "
        "PR-to-ticket auto-close preparation workflow. Use configured "
        "Atlassian/Jira connector tools only. "
        f"Issue: {issue_key} ({issue_url}). "
        f"GitHub PR: {pr_url}. PR title: {pr_title!r}. "
        "Goals: verify the Jira issue exists; attach or link the GitHub PR to "
        "the Jira issue if the connector exposes a remote-link/web-link "
        "operation; add this concise Jira comment if an equivalent comment is "
        f"not already present: {comment!r}. "
        "Do not transition the issue to Done, Closed, or Resolved. Do not make "
        "unrelated field edits. If a transition is needed for 'ready for merge' "
        "or 'in review' and is clearly available, use the least-final matching "
        "transition only. Return concise Markdown with changes made, skipped "
        "idempotent work, and any permission/tool limitations."
    )


def parse_tools(raw_tools: Sequence[str]) -> tuple[str, ...]:
    tools: list[str] = []
    for raw in raw_tools:
        tools.extend(part.strip() for part in raw.split(",") if part.strip())
    return tuple(tools) or DEFAULT_JIRA_TOOLS


def run_gh(args: Sequence[str]) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(["gh", *args], capture_output=True, text=True, check=False)
    if result.returncode != 0:
        command = "gh " + " ".join(args)
        print(f"{command} failed:\n{result.stderr.strip()}", file=sys.stderr)
        raise SystemExit(result.returncode)
    return result


def pr_view_args(pr_url: str | None) -> list[str]:
    args = ["pr", "view"]
    if pr_url is not None:
        args.append(pr_url)
    args.extend(["--json", "url,title,body"])
    return args


def load_pr(pr_url: str | None) -> dict[str, str]:
    result = run_gh(pr_view_args(pr_url))
    data = json.loads(result.stdout)
    return {
        "url": str(data["url"]),
        "title": str(data["title"]),
        "body": str(data.get("body") or ""),
    }


def update_pr_body(*, pr_url: str, body: str) -> None:
    run_gh(["pr", "edit", pr_url, "--body", body])


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Prepare a Jira issue and GitHub PR for auto-close on merge."
    )
    parser.add_argument("issue_key", help="Jira issue key, e.g. INFRA-16727")
    parser.add_argument(
        "--pr-url",
        help="GitHub PR URL. Defaults to gh pr view for the current branch.",
    )
    parser.add_argument(
        "--comment",
        help="Jira comment to add. Defaults to a short auto-close preparation note.",
    )
    parser.add_argument(
        "--max-budget-usd",
        default="2",
        help="Maximum delegated Claude connector budget. Default: 2.",
    )
    parser.add_argument(
        "--jira-tool",
        action="append",
        default=[],
        help=(
            "Allowed Jira connector tool or comma-separated tools. "
            "Default: mcp__claude_ai_Atlassian__*."
        ),
    )
    parser.add_argument(
        "--skip-pr",
        action="store_true",
        help="Do not edit the GitHub PR body.",
    )
    parser.add_argument(
        "--skip-jira",
        action="store_true",
        help="Do not delegate Jira attach/comment work.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print planned PR and Jira work without writing.",
    )
    output_group = parser.add_mutually_exclusive_group()
    output_group.add_argument(
        "--json",
        action="store_const",
        const="json",
        default="auto",
        dest="output_mode",
        help="Keep delegated Claude output as a single JSON result.",
    )
    output_group.add_argument(
        "--human",
        action="store_const",
        const="human",
        dest="output_mode",
        help="Stream progress and print the delegated Markdown report.",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    output_mode = choose_output_mode(args.output_mode, sys.stdout)
    progress_output = sys.stderr if output_mode == "json" else sys.stdout
    try:
        issue_key = normalize_issue_key(args.issue_key)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    pr = load_pr(args.pr_url)
    comment = args.comment or f"Prepared for auto-close on PR merge: {pr['url']}"
    new_body = ensure_pr_body_autoclose(pr["body"], issue_key)

    if args.dry_run:
        print(f"PR: {pr['url']}", file=progress_output)
        print(f"Issue: {issue_key} ({jira_issue_url(issue_key)})", file=progress_output)
        if args.skip_pr:
            print("PR body update: skipped", file=progress_output)
        elif new_body == pr["body"]:
            print("PR body update: already prepared", file=progress_output)
        else:
            print("PR body update: would add:", file=progress_output)
            print(autoclose_line(issue_key), file=progress_output)
        if args.skip_jira:
            print("Jira delegation: skipped", file=progress_output)
        else:
            print(
                "Jira delegation: would attach/link PR and add comment:",
                file=progress_output,
            )
            print(comment, file=progress_output)
        return 0

    if args.skip_pr:
        print("Skipped GitHub PR body update", file=progress_output)
    elif new_body == pr["body"]:
        print(
            f"GitHub PR already has an auto-close line for {issue_key}",
            file=progress_output,
        )
    else:
        update_pr_body(pr_url=pr["url"], body=new_body)
        print(
            f"Updated GitHub PR body with auto-close line for {issue_key}",
            file=progress_output,
        )

    if args.skip_jira:
        print("Skipped Jira attach/comment delegation", file=progress_output)
        return 0

    prompt = build_jira_prompt(
        issue_key=issue_key,
        pr_url=pr["url"],
        pr_title=pr["title"],
        comment=comment,
    )
    return run_delegate(
        allowed_tools=parse_tools(args.jira_tool),
        prompt=prompt,
        max_budget_usd=args.max_budget_usd,
        output_mode=output_mode,
    )


if __name__ == "__main__":
    raise SystemExit(main())
