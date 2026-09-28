---
name: repo-creation
description: Use whenever creating, cloning, or setting up a Git repository, including new GitHub repos, forks, and existing local repos that need a remote. Use the fish clone/clone-work workflow instead of raw git clone or an unconfigured git init.
---

# Repository creation

Read `~/.config/fish/functions/clone.fish` and `clone-common.fish` before acting; they are the source of truth. For personal repos, use `clone OWNER/REPO` in fish from the intended parent directory; for work repos, use `clone-work OWNER/REPO` (both call `clone-common`). Ensure `gh` uses the same account as the SSH alias; scope a personal `GH_TOKEN` from `gh auth token --user PeterCardenas` to the invocation when the active account differs, without printing it.

If the remote does not exist yet, confirm owner and visibility, create it, **then clone with the fish function** rather than `git init` + a hand-made remote. For an already-initialized local repo, do not overwrite or re-clone it: reproduce `clone-common`'s remote SSH alias, user name/email, signing key, `commit.gpgSign=true`, and `gh repo set-default`, checking against the matching reference Git repo first.

Preserve dirty work and unrelated remotes. Check the resulting configuration and upstream before committing or pushing; never publish a public repo without explicit confirmation.
