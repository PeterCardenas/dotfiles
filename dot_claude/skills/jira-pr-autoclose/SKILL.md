---
name: jira-pr-autoclose
description: Prepare a Jira issue and GitHub pull request for auto-close on merge. Use when the user asks to attach/link a Jira ticket to a PR, add a Jira close line to a PR, prep a ticket for auto-close, or connect a GitHub PR with a Jira issue.
---

# Jira PR Autoclose

Use `jira-pr-autoclose` when a user explicitly wants a Jira ticket and GitHub PR connected for merge-time close automation.

## Safety Model

This workflow writes to GitHub and may write to Jira. Only run it when the user asks to attach/link/prep the ticket and PR. Do not transition Jira issues to Done, Closed, or Resolved before the PR is merged.

## Command

```bash
jira-pr-autoclose INFRA-12345 --pr-url https://github.com/org/repo/pull/123
```

Options:
- `--pr-url <url>`: target a specific PR. If omitted, the command uses `gh pr view` for the current branch.
- `--dry-run`: show the planned PR body and Jira work without writing.
- `--skip-pr`: skip editing the GitHub PR body.
- `--skip-jira`: skip Jira attach/comment delegation.
- `--comment <text>`: override the Jira comment.

## Workflow

1. If the issue key or PR is ambiguous, clarify before running the command.
2. Prefer `--dry-run` first when the user has not already confirmed writes.
3. Run the command. It idempotently adds a `Fixes [KEY](Jira URL).` line to the PR body.
4. Read the delegated Jira JSON output. Report what was attached, commented, skipped as already done, or blocked by connector permissions.

## Failure Cases

If the Jira connector lacks write permission or the browser/connector is not authenticated, report the exact blocker. Do not pretend the ticket was prepared.
