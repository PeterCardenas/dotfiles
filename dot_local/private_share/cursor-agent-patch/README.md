# agent-patched ACP hotfix

This directory contains a runtime patch for Cursor Agent CLI ACP mode.

## Problems

In ACP mode, some runs emit `tool_call` from `partialToolCall` before
`readToolCall` and `grepToolCall` args are available. The emitted `rawInput`
becomes `{}` after JSON serialization (undefined fields are dropped). The
`sentToolCalls` set then blocks re-emission on `toolCallStarted`, so richer
args never reach the host client.

Also in ACP chat mode, `stop` and `beforeSubmitPrompt` execution was gated only
on Cursor hooks (`~/.cursor/hooks.json`) and ignored Claude hooks loaded from
`~/.claude/settings.json`, so Claude `Stop` hooks were not invoked.

## Fix strategy

The preload module patches ACP bundles at load time:

- `7414.index.js` (`./src/acp/agent-session.ts`)
  - adjust the `partialToolCall` send path
  - only send/add when extracted input has a defined value OR locations exist
  - wire `hookExecutor` into ACP session instances
  - capture assistant output chunks per prompt and pass
    `last_assistant_message` to stop checks
  - run `~/.claude/hooks/stop_check_links.py` directly as an ACP fallback when
    hook-exec stop payloads omit assistant text
- `1357.index.js` (`../hooks-exec/dist/index.js`)
  - bridge Claude `stop` / `beforeSubmitPrompt` hooks into Cursor `userHooks` and
    `projectHooks` at load time so ACP paths that only inspect Cursor hook sets
    can still see Claude hooks
- `7434.index.js` (`../agent-ui-state/dist/index.js`, when loaded)
  - expand `stop`/`beforeSubmitPrompt` gate checks to include Claude hook sets

This keeps `toolCallStarted` free to emit the first real tool card with richer
`rawInput`.

### Root cause found

In ACP server mode (`agent acp`, used by `agentic.nvim`), stop hooks were loaded
but received payloads with `transcript_path: null` and no `last_assistant_message`.
`stop_check_links.py` therefore returned `{}` and could not block/rewrite.
The loader now captures assistant chunks and provides `last_assistant_message`
to stop enforcement in ACP.

## Files

- `~/.local/bin/agent-patched`: wrapper command
- `~/.local/share/cursor-agent-patch/acp-rawinput-hotfix-loader.cjs`: loader

## Version pinning

`agent-patched` is pinned by default to a specific Cursor Agent build:

- default pinned version: `2026.04.16-2d20146`
- default pinned binary path:
  - `~/.local/share/cursor-agent/versions/2026.04.16-2d20146/cursor-agent`

The wrapper enforces that the resolved binary matches the pinned version suffix.
You can override for controlled testing:

- `CURSOR_AGENT_PATCH_PINNED_VERSION=<version>`
- `CURSOR_AGENT_BIN=<absolute-path-to-cursor-agent>`

The wrapper exports `CURSOR_AGENT_PATCH_SESSION_VERSION` so the loader can
verify runtime version consistency at module load.

## Hiccups seen while updating to `2026.04.16-2d20146`

- **Pin drift breaks silently if not refreshed**: `~/.local/bin/agent` advanced
  to `2026.04.16-2d20146` while wrapper pin was still `2026.04.15-dccdccd`.
  Fix: bump both wrapper pin default and loader expected version together.
- **`session/new` request schema tightened**: ACP now rejects missing
  `mcpServers` with `invalid_type` for `["mcpServers"]`. Use `mcpServers: []`
  in probes/harnesses.
- **`acp --help` is insufficient for patch verification**: it only loads
  top-level `index.js`. Run a real ACP session/prompt path (or agentic.nvim run)
  to ensure `1357` and `7414` patch points are actually loaded and patched.
- **Chunk load set changed**: on this build an additional chunk (`2556.index.js`)
  appears in agentic runs. This does not currently break the patch, but confirms
  startup graph churn between versions.
- **Stop payload gap in ACP**: hook-exec stop payloads may omit assistant text
  (`transcript_path` null). The loader fallback in `7414` now covers this.

## Validate after updates

1. Resolve current agent version path:
   - `readlink -f ~/.local/bin/agent`
2. Check if the old snippet still exists in the loaded ACP chunk:
   - search for `this.sentToolCalls.add(t.message.value.callId),yield this.sendToolCall({toolCallId:t.message.value.callId,title:n,kind:s,rawInput:this.extractToolCallInput(o),locations:this.extractToolCallLocations(o)})`
3. Run with debug:
   - `CURSOR_AGENT_PATCH_DEBUG=1 agent-patched acp ...`
   - expect stderr lines like:
     - `rawInput=yes` when `7414.index.js` is patched
     - `claudeBridge=yes` when `1357.index.js` is patched
     - `stopGate>0` / `beforeSubmit>0` when `7434.index.js` is patched
   - note: for full validation, run through a real ACP session/prompt flow so
     chunked modules are actually loaded
4. Confirm version check:
   - mismatched runtime should fail fast with:
     - `session version mismatch: expected ..., runtime ...`
5. Confirm `tool_call.rawInput` for read/grep is no longer always `{}`.
6. Confirm whether `Stop` hook requests are emitted in your ACP runtime path.

## If this breaks on new releases

Update the patch snippets/regex in `acp-rawinput-hotfix-loader.cjs` to match new
minified snippets around:

- `case"partialToolCall"`
- `this.sentToolCalls.add(...rawInput:this.extractToolCallInput(o)...`
- `return this.dedupeClaudeHooksAgainstCursorHooks(t),t`
- `executeHookForStep(f._E.stop,`
- `executeHookForStep(f._E.beforeSubmitPrompt,`

Keep changes minimal and limited to that single send path.
