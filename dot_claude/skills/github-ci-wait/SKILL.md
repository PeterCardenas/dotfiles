---
name: github-ci-wait
description: "MUST use whenever waiting on, monitoring, or iterating with GitHub PR checks (GitHub Actions, Buildkite statuses, Cursor Bugbot, review bots) — e.g. 'iterate with CI until green', 'make sure CI passes', 'fix CI', 'wait for bugbot', 'merge once green', or any push to a PR whose result matters. Replaces gh pr checks --watch, gh run watch, bk build watch, and sleep loops with one bounded script and a fixed fail/fix/rerun loop."
---

# GitHub CI Wait

One script, one loop. Do not improvise watchers.

```bash
~/.claude/skills/github-ci-wait/scripts/wait_for_pr_checks.py [PR]
```

Run it with a tool timeout of **600s** (the default budget is 540s). It watches the PR's current head SHA through the REST API, prints only the checks that haven't passed, and ends with one `RESULT:` line.

| Exit | Meaning | Next action |
|------|---------|-------------|
| 0 | All checks passed; also prints `UNRESOLVED_THREADS` | Handle any threads (step 4), then finish |
| 1 | A check failed (fail-fast) | Fix it (step 3) |
| 8 | Still pending at budget | Rerun the **identical** command |
| 3 | PR head moved | Rerun; ignore results for the old SHA |
| 4 | No checks registered | Check the push, base branch, and workflow triggers; report if still empty |
| 2 | gh/API error | Fix auth/args; don't fall back to ad-hoc loops |

## Loop

1. Push, then run the script. Wait for results only when the next step needs them; otherwise start independent work first.
2. On exit 8, rerun the identical command. Don't change the interval, add log files, or switch to `--watch`.
3. On exit 1, look at the failure before you wait for anything else:
   - Actions: `gh run view <run-id> --log-failed | tail -200` (the run ID is in the printed URL).
   - Buildkite: use the `buildkite-cli` skill (`bk job log`). If SSO has expired, ask the user to log in. Don't guess.
   - Reproduce locally, fix the root cause, run targeted tests, push, and go back to step 1.
   - Rerun without a code change (`gh run rerun <id> --failed`) only if the evidence shows a flake: the failure is unrelated to the diff and passes on the base branch or on a rerun. Allow one rerun at most.
4. On exit 0 with unresolved threads (Bugbot or reviewers): for each valid finding, fix it and push, which restarts the loop. For each invalid one, resolve the thread through the API with a one-line reason. Don't reply to human reviewers' comments.
5. Stop and report if the same check fails 3 times after fixes, the failure also happens on the base branch, or fixing it needs access or a decision only the user can provide.

## Turn-ending rule

If the user asked for green, passing, merged, or "iterate until…", **don't end the turn while checks are pending**. Keep rerunning step 2. If the user asked you to stay responsive (async subagents), give the loop to an async child and say it's running. Reporting "CI still running" is acceptable only when the user didn't ask you to wait.

## Never

- `gh pr checks --watch` or `gh run watch`: they hit tool timeouts and the GraphQL rate limit, and they watch stale runs after a new push.
- `bk build watch` in parallel with a GitHub watcher. Buildkite already reports to GitHub as commit statuses, so the script covers it.
- `sleep` / `for i in $(seq …)` polling loops, or several watchers on the same PR.
- Claiming green from local tests, an older SHA, or a subset of checks.

## Final report

Include the head SHA, the `RESULT` line, the failing or flaky checks with links, the threads you resolved, and the link to the PR's checks page.
