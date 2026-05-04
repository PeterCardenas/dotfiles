---
name: sync-lazy-plugin
description: Sync edits from a lazy.nvim checkout into the real source repo, push them, refresh the installed checkout through Lazy, and update the matching chezmoi lockfile or plugin spec. Use for `/sync-lazy-plugin` or when lazy checkout edits must become real repo commits plus a matching Lazy update.
---

# Sync Lazy Plugin

Default `/sync-lazy-plugin` flow:

1. start from edits in `~/.local/share/nvim/lazy/<plugin>`
2. move them into the real repo, usually `~/projects/<repo>`
3. commit and push there
4. refresh with `Lazy update <plugin>`
5. commit the resulting chezmoi lockfile or plugin-spec change

## Core Rules

- Treat the dirty lazy checkout as the source of truth. Never commit there.
- Commit only in the real source repo.
- If the source repo is missing, you must use the real fish `clone` function: `fish -lc 'clone owner/repo'` from `~/projects`.
- Do not use `git clone`. Do not reimplement `clone` in bash. Do not work around a failed `clone`.
- Read `~/.config/fish/functions/clone.fish`, any helper it calls such as `clone-common.fish`, and `~/.config/fish/functions/setup_fork.fish` before using them.
- If `clone` fails, stop and ask. That failure is a blocker.
- Use `setup_fork` only through the real fish helper.
- Prefer plugin-spec metadata from chezmoi. Fall back to lazy-checkout remotes only if needed.
- Update `lazy-lock.json` through Lazy, not by hand.
- Move changes with git patches, not manual copy or reconstruction.
- Stage only files relevant to this workflow.
- Stop and ask when discovery is ambiguous or repo state is unsafe.

## 1. Discover Locations And Branch Plan

Identify:

1. lazy checkout path
2. real source repo path
3. chezmoi repo path and tracked `lazy-lock.json`

Default discovery:

1. infer the plugin name from the request, active file, or dirty path under `~/.local/share/nvim/lazy/<plugin>`
2. find the matching plugin spec in chezmoi, usually under `dot_config/nvim_conf/**`
3. prefer from the spec:
   - fork repo from the first repo string
   - fork branch from `branch`
   - upstream repo from `upstream`
   - upstream base branch from `upstream_branch`
4. fill remaining gaps from the lazy checkout remotes
5. set the source repo path to `~/projects/<repo>`

Before changing anything, inspect how the plugin is pinned in chezmoi:

- if pinned to a branch, publish to that branch unless told otherwise
- if pinned to a tag, commit, or other non-branch ref, stop and ask what branch to track
- use `upstream_branch` as the base branch when present; otherwise use the upstream default branch

## 2. Inspect State First

Lazy checkout:

- `git status --short --branch`
- `git symbolic-ref --short -q HEAD`
- `git remote -v`
- `git log --oneline -5`

Real source repo:

- `git status --short --branch`
- `git branch --show-current`
- `git rev-parse --abbrev-ref --symbolic-full-name @{u}`
- `git remote -v`
- `git log --oneline -8`

Chezmoi:

- `git status --short --branch`
- identify the plugin spec file and tracked `lazy-lock.json`

Notes:

- A detached lazy checkout is normal. `git symbolic-ref --short -q HEAD` exiting 1 there is expected.
- Do not chain these inspection commands with `&&` when one may legitimately return non-zero.
- If the source repo is missing, create it before continuing.
- If the source repo is behind its tracked branch, fetch and fast-forward before applying changes.

## 3. Stop And Ask

Stop and ask if:

- you cannot identify a single plugin
- you cannot map the lazy checkout to a single plugin spec or repo slug
- the plugin spec is not pinned to a branch
- `clone` fails
- `setup_fork` fails or still leaves no writable remote
- the source repo has unrelated changes that would mix into the requested commits
- the requested commit split is ambiguous
- the chezmoi repo has an active git client, a lock file, or unrelated staged changes you might disturb

Use a short repo-state summary plus a direct question.

## 4. Prepare The Source Repo

- Prefer an existing writable source clone when present.
- The default source repo location is `~/projects/<repo>`.
- If the repo is missing, run `fish -lc 'clone owner/repo'` from `~/projects`.
- If `clone` fails, stop. Do not fall back to manual cloning.
- If the repo lacks the right `origin`, `upstream`, or writable remote, run `fish -lc 'setup_fork'`.
- Verify the repo ends with the expected branch, `origin`, `upstream`, and a writable remote.
- If you need a branch that already exists in the lazy checkout fork, fetch it into the source repo before checking it out.

## 5. Move Changes Into The Real Source Repo

- Do not hand-copy edits.
- For committed lazy-checkout work, use `git format-patch --stdout <base>..HEAD > /tmp/<plugin>-commits.patch` and apply it in the source repo with `git am -3 /tmp/<plugin>-commits.patch`.
- For uncommitted tracked changes, use `git diff --binary --relative > /tmp/<plugin>-worktree.patch` and apply it with `git apply --3way --index /tmp/<plugin>-worktree.patch`.
- `git diff --binary --relative` does not include untracked files. Export those separately with `git diff --binary --no-index -- /dev/null <path>`.
- `git diff --no-index` exits 1 when it finds differences; treat that as expected and verify the patch file exists.
- If only part of the lazy checkout should move, scope the export with `git diff --binary --relative -- <paths...>`.
- If `git am` or `git apply` fails, stop and ask.
- Split into multiple commits only when the user asked for that.
- Follow the target repo's validation instructions before pushing.

## 6. Validate, Commit, And Push

- Stage only the files for the current logical change.
- Match the repo's existing commit message style.
- Run the repo's validation steps before pushing.
- If validation is blocked by setup or tooling, summarize the blocker and ask whether to push anyway.
- If validation runs and fails, stop and ask before pushing.

## 7. Refresh Lazy And Update Chezmoi

After the source repo commits are pushed:

- clear temporary tracked edits from the lazy checkout, for example with `git restore`
- list untracked cleanup candidates first, then remove only the ones created by this workflow
- if chezmoi pins the plugin branch and it must change, update the plugin spec before running Lazy
- run the real update through the user's config, for example `nvim --headless "+Lazy! update <plugin>" "+qa"`
- prefer a real Lazy update over hand-editing the lockfile
- expect the installed lazy checkout to end detached at the resolved commit

Then in chezmoi:

- inspect repo status
- identify the lockfile change from the Lazy update
- stage only `lazy-lock.json` and any plugin-spec file that changed
- commit and push those files without touching unrelated dotfile changes

## 8. Git Lock Safety

- If git reports a `*.lock` file and another git process or UI is active, do not delete the lock. Ask the user to close it first.
- Only clear a stale lock when no active git process is using the repo and the user wants it cleared.

## Output

Summarize:

- source repo path and branch
- commits created and pushed
- resulting plugin commit after `Lazy update`
- chezmoi files updated, including lockfile and plugin spec if applicable
- anything still blocked on the user
