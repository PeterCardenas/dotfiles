# agent-patched ACP hotfix

This directory contains a runtime patch for Cursor Agent CLI ACP mode.

## Problem

In ACP mode, some runs emit `tool_call` from `partialToolCall` before
`readToolCall` and `grepToolCall` args are available. The emitted `rawInput`
becomes `{}` after JSON serialization (undefined fields are dropped). The
`sentToolCalls` set then blocks re-emission on `toolCallStarted`, so richer
args never reach the host client.

## Fix strategy

The preload module patches the ACP bundle at load time:

- target logic in `./src/acp/agent-session.ts`
- only adjust the `partialToolCall` send path
- only send/add when extracted input has a defined value OR locations exist

This keeps `toolCallStarted` free to emit the first real tool card with richer
`rawInput`.

## Files

- `~/.local/bin/agent-patched`: wrapper command
- `~/.local/share/cursor-agent-patch/acp-rawinput-hotfix-loader.cjs`: loader

## Validate after updates

1. Resolve current agent version path:
   - `readlink -f ~/.local/bin/agent`
2. Check if the old snippet still exists in the loaded ACP chunk:
   - search for `this.sentToolCalls.add(t.message.value.callId),yield this.sendToolCall({toolCallId:t.message.value.callId,title:n,kind:s,rawInput:this.extractToolCallInput(o),locations:this.extractToolCallLocations(o)})`
3. Run with debug:
   - `CURSOR_AGENT_PATCH_DEBUG=1 agent-patched acp ...`
   - expect a stderr line: `[agent-patched] applied ACP rawInput patch ...`
4. Confirm `tool_call.rawInput` for read/grep is no longer always `{}`.

## If this breaks on new releases

Update `BEFORE` and `AFTER` in `acp-rawinput-hotfix-loader.cjs` to match the new
minified snippet around:

- `case"partialToolCall"`
- `this.sentToolCalls.add(...rawInput:this.extractToolCallInput(o)...`

Keep changes minimal and limited to that single send path.
