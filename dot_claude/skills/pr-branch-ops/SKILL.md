---
name: pr-branch-ops
description: "Use this skill whenever changing GitHub PR branch history or topology: rebasing a PR onto master or another base, amending and force-pushing, splitting or retargeting PR branches, deleting a PR branch, or operating on a dependent PR stack. It detects dependents first, uses lease-protected pushes, verifies the resulting PR, and applies stricter bottom-up safeguards for stacks and CODEOWNERS recovery. Do not use for ordinary local-only Git work that does not affect a PR branch."
---

# PR Branch Operations

Use this for history or topology changes to branches backing GitHub pull requests. Start with one common workflow, then choose standalone or stacked handling after checking whether another open PR uses the branch as its base.

## Common Safety Workflow

Before changing a PR branch:

1. Inspect the worktree and branch relationship:
   ```bash
   git status --short --branch
   git remote -v
   git fetch origin
   gh pr view --json number,url,state,baseRefName,headRefName,mergeStateStatus,reviewDecision,reviewRequests
   ```
2. Stop rather than sweep unrelated staged, unstaged, or untracked work into the operation. Preserve active worktrees and commits that belong to another task.
3. Read the PR description, comments, reviews, and unresolved threads when they affect the requested operation.
4. Identify open dependents before rewriting, retargeting, merging, or deleting the branch:
   ```bash
   gh pr list --state open --base '<head-branch>' --json number,title,headRefName,baseRefName,url
   ```
5. Compare the intended and actual history before changing it:
   ```bash
   git log --oneline --decorate --graph origin/base..HEAD
   git diff --name-status origin/base...HEAD
   ```

If there are open dependents, use the stacked workflow. Otherwise use the standalone workflow.

## Standalone PR Workflow

For a standalone rebase, amend, or base change:

1. Confirm the requested base branch and fetch its current remote tip.
2. Rebase onto the remote base rather than a stale local branch.
3. Resolve conflicts according to the intent of both sides; abort and ask if the intents conflict.
4. Run relevant tests before pushing.
5. Push rewritten history with `--force-with-lease`, never plain `--force`.
6. Verify the remote PR afterward:
   ```bash
   gh pr view --json baseRefName,headRefName,commits,files,mergeStateStatus,reviewDecision,reviewRequests
   ```
7. Report tests, push result, current CI state, and any remaining blocker.

For splitting work into independent PRs, branch each PR from the requested remote base, keep commits scoped, verify neither branch contains the other's diff, and set both PR bases explicitly.

## Stacked PR Workflow

Treat every non-tip stack branch as shared infrastructure because another PR compares against it.

Before rewriting the stack:

1. Map the stack bottom-up from PR base/head relationships.
2. Capture each affected PR's base, head, commit list, changed files, review requests, and unresolved threads.
3. Inspect internal commit churn, not only final trees:
   ```bash
   git log --oneline --name-status origin/base..origin/head
   ```
4. Do not temporarily rewind or delete a branch used as an open PR's base.

To amend an earlier stack commit:

1. Create a fixup commit from the tip when practical.
2. Autosquash from the true bottom base while updating local stack refs:
   ```bash
   GIT_SEQUENCE_EDITOR=: git rebase --interactive --autosquash --update-refs <bottom-base>
   ```
3. Verify every local stack ref points to the intended rewritten commit.
4. Push bottom-up with `--force-with-lease`.
5. After each push, verify that PR's base, commits, files, and requested reviewers before continuing.

If a lease fails, stop, fetch, and inspect the remote update rather than overwriting it.

## Retargeting, Closing, and Deleting

Before retargeting or deleting a PR branch:

1. List every dependent PR.
2. Decide and verify the new base for each dependent.
3. Retarget dependents before deleting their old base branch.
4. Re-check each dependent diff after retargeting.

Do not assume GitHub will preserve a dependent PR's intended diff when its base branch disappears.

## Merging a Stack

Merge only when explicitly requested. Do not convert “merge” into auto-merge unless auto-merge was explicitly requested.

For each layer, bottom-up:

1. Confirm approval, green required checks, resolved blocking threads, expected diff, and allowed merge method.
2. Merge the current bottom PR without deleting a branch still needed by an open dependent.
3. Fetch the updated target branch.
4. Rebase the next PR onto the new remote target.
5. Force-push with lease and wait for fresh CI.
6. Re-verify commits, files, review state, and dependents before merging the next layer.

Repeat the merge → fetch → rebase → push → wait cycle instead of merging several stale layers at once.

## CODEOWNERS and Review Recovery

Unexpected reviewers after a rewrite do not by themselves prove the rebase is wrong.

1. Verify the current base/head, commits, and changed files first.
2. Check CODEOWNERS for the current paths.
3. Inspect review-request events and unresolved review threads.
4. Remove only requests clearly caused by a transient incorrect diff or the agent's own workflow; preserve legitimate owners.
5. Resolve addressed threads before re-requesting review. Re-request only if approval is still required afterward.
6. Re-query and report the final reviewer set.

Avoid recovering a closed stack PR by temporarily pushing an old SHA to a branch with open dependents. Prefer retargeting dependents or creating a replacement PR. Ask before an unavoidable temporary rewind.

## Final Report

Report:

- Whether the PR was standalone or stacked and how that was determined.
- Branches rebased, retargeted, created, deleted, or force-pushed.
- PRs merged and whether auto-merge remained disabled.
- Tests and post-push verification performed.
- Current CI/review blockers.
- Reviewer requests changed and why.
