---
name: sync-lazy-plugin
description: Workflow for `/sync-lazy-plugin`: move edits from a lazy.nvim checkout into the real source repo, push them there, refresh the installed checkout through Lazy, and update the matching chezmoi lockfile or plugin spec. Use this whenever the user wants lazy checkout edits turned into real repo commits plus a matching Lazy update.
---

# Sync Lazy Plugin

Run this as the default `/sync-lazy-plugin` workflow, not a questionnaire. The normal path is:

- start from edits in `~/.local/share/nvim/lazy/<plugin>`
- move them into the real source repo, usually `~/projects/<repo>`
- commit and push there
- clear the temporary lazy checkout changes
- run `Lazy update <plugin>`
- commit the resulting `lazy-lock.json` change, plus any needed plugin-spec branch change, from chezmoi

## Core Rules

- Treat the dirty lazy checkout as the source of truth for the requested edits, but never commit there.
- Commit only in the real source repo.
- Use the real fish helpers `clone` and `setup_fork`; do not recreate them in bash.
- Prefer plugin-spec metadata from chezmoi, and fall back to lazy checkout remotes only when needed.
- Update `lazy-lock.json` via Lazy, not by hand.
- Move changes with git patches, not manual copy or "recreate the edits" work.
- Stage only files relevant to this workflow.
- Stop and ask when discovery is ambiguous or repo state is unsafe.

## 1. Discover Locations And Branch Plan

Identify:

1. the lazy.nvim checkout path
2. the real source repo path
3. the chezmoi repo path and tracked `lazy-lock.json`

Default discovery flow:

1. infer the plugin name from the user request, active file, or dirty checkout path under `~/.local/share/nvim/lazy/<plugin>`
2. locate the matching plugin spec in chezmoi, usually under `dot_config/nvim_conf/**`
3. from that spec, prefer:
   - fork repo from the first repo string
   - fork branch from `branch`
   - upstream repo from `upstream`
   - upstream base branch from `upstream_branch`
4. fill any gaps from the lazy checkout remotes
5. set the source repo path to `~/projects/<repo>`, where `<repo>` is the repo name from the fork or upstream slug

Before using helpers, read:

1. `~/.config/fish/functions/clone.fish`
2. any helper it calls, especially `clone-common.fish`
3. `~/.config/fish/functions/setup_fork.fish`

Then use the real helpers:

- `fish -lc 'clone owner/repo'` from `~/projects` if the source repo is missing
- `fish -lc 'setup_fork'` inside the source repo if remotes are not ready

If a helper may prompt in a way that changes the workflow, ask instead of guessing.

Before changing anything, inspect how the plugin is pinned in chezmoi:

- if it is pinned to a branch, publish to that branch unless the user asked otherwise
- if it is pinned to a tag, commit, or any other non-branch ref, stop and ask what branch to track
- use `upstream_branch` as the base branch when present; otherwise use the upstream default branch

## 2. Inspect State First

For the lazy.nvim checkout, run:

- `git status --short --branch`
- `git symbolic-ref --short -q HEAD`
- `git remote -v`
- `git log --oneline -5`

For the real source repo, run:

- `git status --short --branch`
- `git branch --show-current`
- `git rev-parse --abbrev-ref --symbolic-full-name @{u}`
- `git remote -v`
- `git log --oneline -8`

For chezmoi, run:

- `git status --short --branch`
- identify the plugin spec file and the tracked `lazy-lock.json`

Notes:

- A detached lazy checkout is normal here. `git symbolic-ref --short -q HEAD` exits 1 on detached HEAD; treat that as expected, not as a blocker.
- Do not chain these inspection commands with `&&` when one may legitimately return non-zero. Run them separately, or use `;` if you want all of them to run anyway.
- If the source repo is missing, create it before continuing.
- If the source repo is behind its tracked branch, fetch and fast-forward before applying changes.

## 3. Stop And Ask Instead Of Guessing

Ask the user if any of these are true:

- you cannot identify a single plugin to sync
- you cannot map the lazy checkout to a single plugin spec or repo slug
- the plugin spec is not pinned to a branch
- `setup_fork` fails or still leaves no writable remote
- the source repo has unrelated changes that would get mixed into the requested commits
- the requested commit split is ambiguous
- the chezmoi repo has an active git client, a lock file, or unrelated staged changes you might disturb

Use a short status summary plus a direct question, for example:

```markdown
Repo state:
- Lazy checkout is detached at `abc1234`
- Source repo is on `dev` and writable
- Chezmoi repo has unrelated staged changes

How would you like me to proceed?
1. Tell me the repo/branch to use
2. Create or configure a fork
3. Use a local-only branch
4. Wait until the other git client is closed
5. Stop here
```

## 4. Prepare The Source Repo

- Prefer an existing writable source clone when one already exists.
- The default source repo location is `~/projects/<repo>`.
- If the repo is missing, run `fish -lc 'clone owner/repo'` from `~/projects`.
- If the repo is missing `upstream`, has the wrong `origin`, or otherwise lacks a writable fork remote, run `fish -lc 'setup_fork'`.
- Verify the repo ends up with the expected branch, `origin`, `upstream`, and a writable remote.
- If you need to base new work on a branch that already exists in the lazy checkout fork, fetch that branch into the source repo before checking it out.

## 5. Move Changes Into The Real Source Repo

- Do not hand-copy edits from the lazy checkout into the source repo. Export patches with git and apply them with git.
- For committed lazy-checkout work, use `git format-patch --stdout <base>..HEAD > /tmp/<plugin>-commits.patch` and apply it in the source repo with `git am -3 /tmp/<plugin>-commits.patch`.
- For uncommitted tracked changes, use `git diff --binary --relative > /tmp/<plugin>-worktree.patch` and apply it with `git apply --3way --index /tmp/<plugin>-worktree.patch`.
- `git diff --binary --relative` does not include untracked files. Export those separately with `git diff --binary --no-index -- /dev/null <path>` and apply those patches too.
- `git diff --no-index` exits 1 when it finds differences; treat that as expected patch-generation success, but verify the patch file exists.
- If only part of the lazy checkout should move over, scope the export with `git diff --binary --relative -- <paths...>`.
- If `git am` or `git apply` fails, stop and ask instead of reconstructing the edits manually.
- Split into multiple commits only when the user asked for that.
- Follow the target repo's validation instructions before pushing.

## 6. Validate, Commit, And Push

- Stage only the files for the current logical change.
- Match the repo's existing commit message style.
- Run the repo's validation steps before pushing.
- If validation is blocked by missing tools, setup, or another non-code issue, summarize the blocker and ask whether to push anyway.
- If validation runs and fails, stop and ask before pushing.

## 7. Refresh Lazy And Update Chezmoi

After the source repo commits are pushed:

- clear the temporary tracked edits from the lazy checkout, for example with `git restore`
- list untracked cleanup candidates first, then remove only the ones clearly created by this workflow
- if chezmoi pins the plugin branch and it needs to change, update the plugin spec before running Lazy
- run the real update through the user's config, for example `nvim --headless "+Lazy! update <plugin>" "+qa"`
- prefer a real Lazy update over hand-editing the lockfile
- expect the installed lazy checkout to end up detached at the resolved commit after the update

Then in chezmoi:

- inspect repo status
- identify the lockfile change produced by the Lazy update
- stage only `lazy-lock.json` and any plugin-spec file that had to change
- commit and push those files without touching unrelated dotfile changes

## 8. Git Lock Safety

If git reports a `*.lock` file and another git UI or process is active in that repo, do not delete the lock. Ask the user to close the other client first.

Only clear a stale lock when both are true:

1. no active git process is using that repo
2. the user wants it cleared

## Output

Summarize:

- source repo path and branch
- commits created and pushed
- resulting plugin commit after `Lazy update`
- chezmoi files updated, including lockfile and plugin spec if applicable
- anything still blocked waiting on the user
