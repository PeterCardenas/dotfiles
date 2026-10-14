---
name: pi-maintenance
description: Maintain Peter's Pi installation and chezmoi configuration. Use when updating Pi or Pi extensions, tracking package versions in dotfiles, debugging extension startup/type errors, stale reloads, subagent failures, settings/model sync, or automatic chezmoi apply for Pi/ACP edits. Also use when changing Pi settings, extensions, hooks, or skills in this dotfiles repo.
---

# Pi maintenance

Work from `/home/pcardenas/.local/share/chezmoi` (paths below are relative to it). Diagnose first; a question is not permission to modify, update, commit, or push.

## Establish the actual state

- Run `git status --short` and inspect existing diffs; preserve unrelated edits in every affected repo.
- Check `command -v pi`, `pi --version`, `pi list`, and `pi update --help`. Compare the active host, `~/.pi/agent/npm/package.json`, and both tracked manifests below. Launcher, runtime, and development types can differ; do not infer runtime version from the global launcher alone.
- Inspect relevant `PI_*` overrides (especially agent/session directories), project `.pi/settings.json`, and live user settings without exposing credentials.
- Resolve the active Pi package and read its local `docs/cli.md`, `docs/packages.md`, and relevant `docs/extensions.md`, `docs/settings.md`, or `docs/skills.md` completely, following relevant links/examples. Consult installed extension docs rather than remembered APIs; do not bake a pnpm store hash into commands.

## Edit the owning source

- **Managed Pi settings:** `.chezmoitemplates/pi-settings.json`, merged by `dot_pi/private_agent/modify_settings.json.tmpl`. Template keys win recursively; managed arrays replace existing arrays; absent keys survive. Keep mutable preferences outside the template unless deliberately taking ownership.
- **Installed runtime/package pins:** `dot_pi/private_agent/npm/package.json` → `~/.pi/agent/npm/package.json`.
- **Local extension development types:** `dot_pi/private_agent/extensions/package.json` and `pnpm-lock.yaml`. These are not the runtime manifest.
- **Extension and agent behavior:** `dot_pi/private_agent/extensions/claude-compat.ts`, `dot_pi/private_agent/agents/reviewer.md`. Reviewer model/thinking belong in template `subagents.agentOverrides`, not duplicate frontmatter.
- **Models:** `.chezmoitemplates/pi-models.json`, `dot_pi/private_agent/modify_models.json.tmpl`, and `executable_merge_models_d.py`. Preserve other repositories' `models.d` fragments.
- **Shared hooks:** `.chezmoitemplates/claude-settings.json`, `dot_claude/hooks/`, and `dot_local/bin/executable_pi-claude-hook-bridge`.
- **Portable skills:** `dot_agents/skills/NAME/SKILL.md` → `~/.agents/skills/NAME/SKILL.md` (discovered by Pi).
- Use `chezmoi source-path TARGET` and `chezmoi target-path SOURCE` to confirm ownership. Provider-specific extensions, web-search configuration, and model fragments may belong to a sibling work-dotfiles repo; inspect that owner too, without copying work-specific configuration into this personal repo.

## Update without losing reproducibility

1. For an authorized update, choose the smallest scope: `pi update` (host), `pi update --extensions` (packages), `pi update SOURCE` (one package), or `pi update --all` (both). Check installed help first; use the owning package manager if it owns host updates.
2. Keep settings sources unversioned (`npm:pi-subagents`, `npm:pi-web-access`) so Pi can update them. Versioned sources are pinned and are not advanced by updates.
3. After updating, capture actual installed versions **before any apply can restore old pins**. Update only relevant dependencies in the tracked runtime manifest to exact versions, without `^`/`~`. Preserve unrelated pending edits; resolve any conflicting version intent with the user. Do not delete the manifest to enable updates.
4. When changing the host, align the local extension development dependency to the intended host version and regenerate its tracked pnpm lockfile using the declared package manager. Do not blindly copy generated manifests or commit runtime `node_modules`/install caches.
5. Confirm installed dependencies match recorded pins. Applying a manifest alone does not reconcile installed dependencies: use Pi's update/install process and recheck.
6. Run validation below against the intended host. Then `/reload` the session or start a fresh Pi/ACP process. Disk installation success does not prove the existing session loaded new code; host updates require a process restart.

## Apply edits through the existing hooks

The shared `Edit|Write` PostToolUse hook performs targeted apply; Pi's compatibility extension forwards tool events into it, including child-session edits when that extension is loaded. Do not restore Neovim `on_file_edit`/`ChezmoiApplyPath` or add full-repo apply on response completion: ACP parent transcripts can hide child edits.

- Edit managed **source**, not the target. Read the hook result and verify the specific target; do not run another manual apply after a reported successful sync.
- `.chezmoitemplates` entries are not targets. Apply/inspect their consuming `modify_*.tmpl` source entries, not the fragment with `--source-path`. The shared hook already finds dependents.
- Bash edits do not emit Edit/Write hooks. If syncing is explicitly required and no hook ran, preview the targeted diff and use `chezmoi apply --source-path SOURCE`; otherwise report the unsynced target. For a new skill whose file-level hook fails on missing target parents, apply only its missing directory source entries parent-first, then preview/apply its individual files. Verify every target; directory-only apply may create parents without installing their files. Do not force through confirmation prompts.
- A `modify_` script must emit desired contents on **stdout**. The settings modifier reads stdin and merges without writing the target itself. Model modifiers intentionally write fragment files, then emit merged output through the helper.
- If `status`/`diff` fails because a target helper is absent, distinguish diagnostic evaluation from apply ordering: real apply installs `merge_models_d.py` before `models.json`. Do not add speculative missing-helper guards. For `/dev/tty` prompts, ask the user to perform the targeted apply in a real terminal rather than forcing overwrite.

## Validate and report

Run the relevant checks from the source repo:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest test_pi_settings_modifier test_pi_migration_followups test_pi_claude_hook_bridge -v
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s dot_claude/hooks -p 'test_*.py' -q
git diff --check
```

- Version-expectation failures can reveal existing drift. Compare the baseline, intended versions, and installed host; update regression expectations only for an intentional contract change, not merely to silence failures.
- For extension/host changes, strict-typecheck `claude-compat.ts` against the **intended host's** declarations (`tsc --noEmit --strict --skipLibCheck --target ES2022 --module NodeNext --moduleResolution NodeNext --types node ...`). Use the existing local dependency tree or a disposable sandbox; narrow message unions before reading `content`, never cast away incompatible types.
- Validate sibling provider extensions/tests if affected. Inspect their typecheck script: a pass against an old hardcoded Pi version does not validate the new host.
- For runtime regressions, reproduce the exact invocation and protocol in isolation. `--no-extensions` disables auto-loaded providers/hooks too; explicitly load required extensions with `-e`. A passing isolated command with different flags is not end-to-end proof.
- Do not launch a subagent smoke test without delegation authorization. If authorized, verify a fresh-process run and its artifacts; on failure, stop and report rather than silently changing execution mode.
- Report source versus installed versus loaded state, changed paths, commands/outcomes, and any baseline failures. Commit/push only when requested, with scoped conventional commits. End with **Key References** using local paths and relevant documentation.
