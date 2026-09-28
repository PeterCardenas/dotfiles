---
name: repo-creation
description: Use whenever creating, cloning, or setting up a Git repository, including new GitHub repos, forks, and existing local repos that need a remote. Use the fish clone/clone-work functions for existing remotes and git-init/git-init-work for new local repos.
---

# Repository creation

Read the installed fish functions `clone`, `clone-work`, `clone-common`, `git-init`, `git-init-work`, and `git-init-common` before acting; they are the source of truth.

- **Remote already exists:** run `clone OWNER/REPO` (personal) or `clone-work OWNER/REPO` (work) in fish from the desired parent directory. Match `gh` to the function's SSH identity; if necessary scope `GH_TOKEN` from `gh auth token --user PeterCardenas` to a personal invocation without printing it.
- **New local repository:** run `git-init NAME` (personal) or `git-init-work NAME` (work) in fish from its parent directory. These create the local repo, configure its SSH origin and signing; they **do not create a GitHub repository**. Confirm owner and visibility before creating the matching remote, then push. Do not precreate-and-clone merely to avoid `git-init`.
- **Local repository already initialized:** from inside it, run `git-init` or `git-init-work` with no name **only when it has no origin**. If it already has an origin, preserve it and compare the matching function's configuration rather than re-cloning or running `git remote add` twice.

Preserve dirty work and unrelated remotes. Check the resulting configuration and upstream before committing or pushing; never publish a public repo without explicit confirmation.
