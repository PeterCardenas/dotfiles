---
name: sync-lazy-plugin
description: End-to-end workflow for `/sync-lazy-plugin`: take edits from a lazy.nvim checkout, publish them from the real source repo, refresh the installed checkout through Lazy, and update the matching chezmoi lockfile/config. Use this whenever the user explicitly runs `/sync-lazy-plugin` or asks to turn lazy checkout edits into proper repo commits plus a matching Lazy update.
---

# Sync Lazy Plugin

Run this skill as a default workflow, not a questionnaire. The goal is that `/sync-lazy-plugin` should usually complete end-to-end without follow-up questions.

Use it for the full plugin workflow, not just a quick git check:

- start from edits in `~/.local/share/nvim/lazy/<plugin>`
- move those edits into the real source repo, usually under `~/projects/<repo>`
- commit and push from the real repo
- clear the temporary lazy checkout changes
- run `Lazy update <plugin>` through the user's actual config
- commit the resulting `lazy-lock.json` change, plus any required plugin-spec branch change, from chezmoi

## Core Rules

- Do not commit from the lazy.nvim checkout.
- Make commits only in the real source repo.
- Do not invent ad hoc clone or fork commands; use the real fish helpers in this environment.
- Do not edit `lazy-lock.json` by hand when Lazy can update it.
- When moving edits from the lazy checkout to the source repo, use git patch commands, not manual copy or vague "recreate the changes" steps.
- Do not stage unrelated chezmoi changes.
- If another git client has a repo locked, stop and ask.

## Defaults

Treat these as the default behavior so the workflow can just run:

- Use the dirty lazy.nvim checkout as the plugin source of truth.
- Use `~/projects/<repo>` as the real source repo path.
- Read and then use the fish helpers `clone` and `setup_fork`; do not reimplement them in bash.
- Prefer repo metadata from the plugin spec in chezmoi. In this setup, plugin specs often include:
  - the fork repo string as the first entry, for example `'PeterCardenas/agentic.nvim'`
  - `branch` for the fork branch to publish
  - `upstream` for the upstream repo
  - `upstream_branch` for the upstream base branch
- If the plugin spec does not expose all of that metadata, fall back to the lazy checkout remotes.
- Only stop and ask when discovery is genuinely ambiguous or the repo state is unsafe.

## 1. Discover The Three Locations

Identify, in this order:

1. the lazy.nvim checkout path
2. the real source repo path
3. the chezmoi repo path and tracked lockfile path

Use concrete defaults instead of asking up front:

1. Determine the plugin name from the user request, active file path, or the dirty lazy checkout path under `~/.local/share/nvim/lazy/<plugin>`.
2. Locate the matching plugin spec in chezmoi, usually under `dot_config/nvim_conf/**`, by searching for the plugin name, fork repo slug, or upstream repo slug.
3. From the plugin spec, prefer these values:
   - fork repo from the first repo string
   - fork branch from `branch`
   - upstream repo from `upstream`
   - upstream base branch from `upstream_branch`
4. If the plugin spec is missing some of those values, derive them from the lazy checkout remotes.
5. Set the source repo path to `~/projects/<repo>` where `<repo>` is the repo name portion of the fork or upstream repo slug.
6. If that source repo path does not exist, create it with the fish `clone` helper.

Read the helper definitions before running them:

1. `~/.config/fish/functions/clone.fish`
2. any helper it calls, especially `clone-common.fish`
3. `~/.config/fish/functions/setup_fork.fish`

Then use the real helpers:

- `clone owner/repo` to clone a source repo and carry over local git identity settings
- `setup_fork` inside the repo when the fork remotes need to be wired up

Typical invocations:

- `fish -lc 'clone owner/repo'` from the directory where the source repo should be created
- `fish -lc 'setup_fork'` from inside the repo whose remotes need to be rewired

If a helper may prompt for input, read its definition first, decide whether the prompt changes the workflow, and ask the user instead of guessing.

Do not just say that you "read" the helpers. Use them.

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

Before doing any repo changes, inspect how the plugin is pinned in chezmoi and derive the branch plan:

- If the plugin spec is pinned to a branch, use that as the fork branch to publish unless the user explicitly asked for something else.
- If the plugin spec is pinned to a tag, commit, or anything other than a branch, stop immediately and ask the user what branch it should track. Do not start the source-repo sync, cleanup, or `Lazy update` work until that is resolved.
- If the plugin spec has `upstream_branch`, use that as the base branch.
- Otherwise, use the upstream repo default branch.

If the source repo path is known but the repo is missing on disk, create it before continuing. If the source repo is behind its tracked branch, fetch and fast-forward before applying changes.

## 3. Stop And Ask Instead Of Guessing

Prompt the user when any of these are true:

- you cannot identify a single plugin to sync
- you cannot map the lazy checkout to a single plugin spec or repo slug
- the plugin spec is not pinned to a branch
- `setup_fork` fails or still leaves no writable remote
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

- Prefer an existing writable source clone when one already exists.
- The default source repo location is `~/projects/<repo>`.
- If the repo is missing, run `fish -lc 'clone owner/repo'` from `~/projects` using the inferred repo slug.
- After cloning, inspect the remotes. If `origin` and `upstream` are already correct and writable, continue.
- If the repo is missing `upstream`, has the wrong `origin`, or otherwise lacks a writable fork remote, run `fish -lc 'setup_fork'` inside the repo.
- Read the helper definitions first so you understand prompts and side effects, then execute the helper itself.
- Verify the repo ends up with the expected fork branch, `origin`, `upstream`, and a writable remote.
- Ask only if the repo slug is unclear or `setup_fork` still does not leave a usable writable remote.
- If you need to base a new branch on work already present in the lazy checkout fork branch, fetch that branch into the source repo before checking out the new branch.

## 5. Move Changes Into The Real Source Repo

- Do not hand-copy edits from the lazy.nvim checkout into the source repo. Export a patch with git in the lazy checkout and apply it with git in the source repo.
- If the lazy checkout already has committed work that needs to move over, export that commit range from the lazy checkout with `git format-patch --stdout <base>..HEAD > /tmp/<plugin>-commits.patch`, then apply it in the source repo with `git am -3 /tmp/<plugin>-commits.patch`.
- If there is remaining uncommitted working-tree state in the lazy checkout, export it from the lazy checkout with `git diff --binary --relative > /tmp/<plugin>-worktree.patch`, then apply it in the source repo with `git apply --3way --index /tmp/<plugin>-worktree.patch`.
- If only part of the lazy checkout should move over, scope the export explicitly with `git diff --binary --relative -- <paths...> > /tmp/<plugin>-worktree.patch` instead of applying the whole working tree.
- If either `git am` or `git apply` fails, stop and ask instead of reconstructing the change manually.
- Split the work into logical commits only when the user asked for multiple commits.
- Follow the target repo's validation instructions before pushing.

## 6. Validate, Commit, And Push In The Source Repo

- Stage only the files for the current logical change.
- Match the repo's existing commit message style.
- Run the repo's validation steps before pushing.
- If validation is blocked by missing tools, environment setup, or another non-code issue, summarize the blocker and ask the user whether to push anyway.
- If validation runs and fails, stop and ask before pushing. Do not treat a real test or lint failure as equivalent to a setup problem.

## 7. Refresh The Lazy Checkout

After the source repo commits are pushed:

- clear the temporary tracked edits from the lazy.nvim checkout, for example with `git restore`
- list any untracked cleanup candidates first and remove only the ones that were clearly created by this workflow
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
