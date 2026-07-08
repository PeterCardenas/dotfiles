---
name: stacked-pr-guard
description: "Use this skill only when a request explicitly involves a PR stack or dependent branch-as-base PRs and changing or recovering those branches: stack rebases, bottom-up force-with-lease pushes, retargeting or reopening dependents, deleting stack branches, or CODEOWNERS noise after stack rewrites."
---

# Stacked PR Guard

Use this when operating on stacked GitHub PRs or branches where one PR's head branch is another PR's base branch. The goal is to preserve clean diffs and reviewer state while rebasing, force-pushing, retargeting, reopening, or merging.

This skill is more specific than generic PR babysitting. If both seem relevant, use this skill first whenever the task includes stack topology, dependent PR base branches, force-push/rebase sequencing, retarget/reopen recovery, or unexpected CODEOWNERS reviewer requests.

## Core Principle

Treat every non-tip branch in a stack as shared infrastructure for dependent PRs. Rewriting, deleting, temporarily rewinding, or merging one branch can cause GitHub to recalculate diffs, close PRs, or request unrelated CODEOWNERS reviewers on every PR above it.

## Required Safety Checks

Before changing any PR branch in a stack:

1. Map the full stack bottom-up:
   ```bash
   gh pr list --state open --json number,title,headRefName,baseRefName,url
   ```
2. Identify dependents for every branch you might push, delete, merge, or retarget:
   ```bash
   gh pr list --state open --base '<branch-name>' --json number,title,headRefName,baseRefName,url
   ```
3. Capture current review requests for every affected PR:
   ```bash
   gh api repos/OWNER/REPO/pulls/PR_NUMBER/requested_reviewers --jq '{users: [.users[].login], teams: [.teams[].slug]}'
   ```
4. Inspect current PR diffs and commit counts before and after the operation:
   ```bash
   gh pr view PR_NUMBER --json number,baseRefName,headRefName,files,commits,reviewRequests
   git diff --name-status origin/base...origin/head
   git log --oneline origin/base..origin/head
   ```
5. Inspect each PR's internal commits, not just the final diff. A PR can have the right final tree while earlier commits add files that later commits delete:
   ```bash
   git log --oneline --name-status origin/base..origin/head
   ```

If a PR branch is the base of another open PR, do not delete it, temporarily push an old SHA to it, or rely on GitHub to retarget dependents correctly.

## Rebasing and Pushing a Stack

Prefer this sequence:

1. Create fixup commits on the tip branch.
2. Autosquash with update refs from the true bottom base:
   ```bash
   GIT_SEQUENCE_EDITOR=: git rebase --interactive --autosquash --update-refs <bottom-base>
   ```
3. Verify each local stack branch points at the intended rewritten commit:
   ```bash
   git log --oneline --decorate -12
   ```
4. Push bottom-up with `--force-with-lease`.
5. After pushing each branch, verify that its PR still has a one-commit or expected diff relative to its base, and that review requests did not expand unexpectedly. If a branch has add/delete churn within its own commits, squash or fixup that branch before continuing.

Never use plain force-push. Never use destructive git reset/checkout unless the user explicitly asks.

## Merging a Stack

Before merging a PR:

1. Confirm the user explicitly asked for merge, or that the current task includes merge.
2. Confirm the PR is approved and required checks are green.
3. Confirm the repository's allowed merge method. If only squash is allowed, understand that dependent PRs may need rebasing or retargeting afterward.
4. Confirm the branch has no open dependent PRs, or plan retargeting before branch deletion:
   ```bash
   gh pr list --state open --base '<branch-being-merged>' --json number,title,headRefName,baseRefName,url
   ```
5. Do not enable auto-merge unless the user explicitly asks for auto-merge. A request to "merge" means merge now if allowed, not "enable auto-merge later."

When a bottom PR is squash-merged, immediately fetch `master`, rebase the next branch onto `origin/master`, push it, wait for fresh CI, then merge it before moving to the next branch. Repeat this merge -> fetch -> rebase -> push -> wait cycle for every layer.

If `gh pr merge` says branch policy prohibits the merge after checks pass, inspect `reviewDecision`, `reviewRequests`, and unresolved review threads before enabling auto-merge or requesting review. Resolve addressed threads first; stale unresolved threads can hide an otherwise valid approval.

## Reopening or Recovering PRs

Be careful with closed stacked PRs. A common failure mode is temporarily pushing an old SHA to a branch so GitHub will reopen a PR, then pushing the rebased SHA back. That can make dependent PRs briefly compare against the wrong base and trigger unrelated CODEOWNERS review requests.

Avoid that recovery path when dependent PRs exist. Prefer one of these:

- Retarget dependent PRs away from the branch before changing it.
- Create a replacement PR from the current branch if GitHub will not reopen the old PR.
- Ask the user before any temporary branch rewind if the branch is a base for open PRs.

If a temporary rewind is unavoidable, treat cleanup as part of the operation:

1. Record review requests before the rewind.
2. After restoring the branch, verify every dependent PR's diff and commit list.
3. Compare requested reviewers against CODEOWNERS for the current diff.
4. Remove stale review requests caused by the transient bad diff, keeping legitimate owners.

## Reviewer Hygiene

When review requests look wrong:

1. Verify the PR diff first. Do not assume the rebase is broken.
2. Check CODEOWNERS for the actual changed paths.
3. Query the event timeline to see when and who requested reviewers:
   ```bash
   gh api repos/OWNER/REPO/issues/PR_NUMBER/events --paginate --jq '.[] | select(.event == "review_requested" or .event == "review_request_removed") | {event: .event, created_at: .created_at, actor: .actor.login, requested_reviewer: .requested_reviewer.login, requested_team: .requested_team.slug}'
   ```
4. Remove stale requests only when they are clearly unrelated to the current diff or were accidentally created by your own workflow:
   ```bash
   gh api -X DELETE repos/OWNER/REPO/pulls/PR_NUMBER/requested_reviewers \
     -f reviewers[]=user-login \
     -f team_reviewers[]=team-slug
   ```
5. Re-query requested reviewers and report the final set.

Do not remove a legitimate CODEOWNER request just because it is inconvenient.

Before re-requesting reviewers after a rebase, check unresolved review threads:
```bash
gh api graphql -f query='query($owner:String!, $repo:String!, $number:Int!) { repository(owner:$owner, name:$repo) { pullRequest(number:$number) { reviewThreads(first:100) { nodes { id isResolved path comments(first:10) { nodes { databaseId author { login } body } } } } } } }' -F owner=OWNER -F repo=REPO -F number=PR_NUMBER
```
If the requested change is addressed, resolve the thread instead of re-requesting review. Only re-request when `reviewDecision` remains unapproved after addressed threads are resolved.

## Final Report Checklist

When done, report:

- Which PRs were actually merged, if any.
- Whether auto-merge was enabled or left disabled.
- Which branches were force-pushed.
- Which PRs still need review or checks.
- Any reviewer requests removed, and why.
- The verification commands that passed.
