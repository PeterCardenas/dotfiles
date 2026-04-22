---
name: sync-lazy-plugin
description: Publishes changes from a lazy.nvim checkout into the real plugin repo, pushes the branch, refreshes the installed lazy checkout through Lazy, and commits the resulting lockfile/config update in chezmoi. Use whenever the user wants to take work from ~/.local/share/nvim/lazy/<plugin> and turn it into proper repo commits plus a matching Lazy lock update.
---

# Sync Lazy Plugin

Run this skill when the user wants the full plugin workflow, not just a quick git check:

- start from edits in `~/.local/share/nvim/lazy/<plugin>`
- move those edits into the real source repo, usually under `~/projects/<plugin>`
- commit and push from the real repo
- clear the temporary lazy checkout changes
- run `Lazy update <plugin>` through the user's actual config
- commit the resulting `lazy-lock.json` change, plus any required plugin-spec branch change, from chezmoi

## Core Rules

- Do not commit from the lazy.nvim checkout.
- Make commits only in the real source repo.
- Do not guess a fork, remote, helper command, or base branch.
- Do not edit `lazy-lock.json` by hand when Lazy can update it.
- Do not stage unrelated chezmoi changes.
- If another git client has a repo locked, stop and ask.

## 1. Discover The Three Locations

Identify:

1. the lazy.nvim checkout path
2. the real source repo path
3. the chezmoi repo path and tracked lockfile path

If the source repo path is missing, ask for it. If the user wants you to use one of their shell helpers such as `clone`, inspect that helper first so you do not guess its argument format.

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

Also inspect how the plugin is pinned in chezmoi before touching anything. If the spec points at a branch like `skip-over-concealed-lines`, you may need to change that pin before `Lazy update` can move to the new branch.

If the source repo is missing, safely create it first. If the source repo is behind its tracked branch, fetch and fast-forward before applying changes.

## 3. Stop And Ask Instead Of Guessing

Prompt the user when any of these are true:

- the lazy checkout is detached and there is no separate writable source repo
- the source repo is not forked yet
- there is no writable remote
- the correct base branch is unclear
- the source repo has unrelated changes that would get mixed into the requested commits
- the requested commit split is ambiguous
- the chezmoi repo has an active git client, a lock file, or unrelated staged changes you might disturb

Use a short status summary followed by a direct question:

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

## 4. Set Up The Source Repo

- Prefer a normal source clone under something like `~/projects/<plugin>`.
- If the user asks for their shell helper, inspect it first, then run it from the intended parent directory.
- Verify the clone has the expected `origin` and `upstream`.
- If you need to base a new branch on work already present in the lazy checkout fork branch, fetch that branch into the source repo before checking out the new branch.

## 5. Move Changes Into The Real Source Repo

- Read the changed files from the lazy.nvim checkout.
- Recreate those edits in the real source repo.
- If the lazy checkout already has committed work on another branch, base the new source-repo branch on that commit first, then apply the remaining working-tree delta on top.
- Split the work into logical commits only when the user asked for multiple commits.
- Follow the target repo's validation instructions before pushing.

## 6. Validate, Commit, And Push In The Source Repo

- Stage only the files for the current logical change.
- Match the repo's existing commit message style.
- Run the repo's validation steps before pushing.
- Continue on with the push even if you're not able to get the validation working (environment/dev setup etc.).

## 7. Refresh The Lazy Checkout

After the source repo commits are pushed:

- clear the temporary tracked edits from the lazy.nvim checkout, for example with `git restore`
- remove any untracked files created by the work
- if chezmoi pins the plugin branch, update that spec to the new branch before running Lazy
- run the actual update through the user's config, for example `nvim --headless "+Lazy! update <plugin>" "+qa"`

Prefer a real Lazy update over hand-editing the lockfile. Expect the installed lazy checkout to end up detached at the resolved commit after the update.

## 8. Commit The Lockfile In Chezmoi

- inspect the chezmoi repo status
- identify the lockfile change produced by the Lazy update
- stage only the `lazy-lock.json` change and any plugin-spec file that had to change to track the new branch
- commit and push those files without touching unrelated dotfile changes

## 9. Git Lock Safety

If git reports a `*.lock` file and another git UI or process is active in that repo, do not delete the lock. Ask the user to close the other client first.

Only clear a stale lock when both conditions are true:

1. no active git process is using that repo
2. the user wants you to clear it

## Output

Summarize:

- source repo path and branch
- commits created and pushed
- resulting plugin commit after `Lazy update`
- chezmoi files updated, including lockfile and plugin spec if applicable
- anything still blocked waiting on the user
