---
name: figma-connector
description: Use this skill for requests to inspect Figma files, designs, nodes, screenshots, variables, libraries, FigJam boards, or design-system assets through Claude's Figma connector. It delegates read-only Figma connector calls to `claude -p` and reports cited results or access limits.
---

# Figma Connector

Use this skill when the current agent needs Figma information that is available through Claude Code's Figma connector but not through the current runtime's tools. Delegate read-only Figma inspection to `claude -p`, then synthesize the returned evidence in the current conversation.

## Safety Model

Keep connector work read-only. The delegated Claude run may inspect Figma file metadata, selected nodes, screenshots, variables, libraries, FigJam content, shader definitions, and design-system assets. It must not create files, edit designs, upload assets, send code-connect mappings, export videos, generate diagrams, comment, publish, or make any external change.

If the user asks for a Figma write/export action, first gather read-only context and ask for explicit confirmation before any write-capable workflow. Never upload local files or data to Figma without explicit user approval.

## Scope Requirements

Most Figma read tools require a concrete Figma file URL, file key, node ID, or existing file context. There is no generic full-text search across all Figma files/projects/comments in the current connector surface.

If the user gives only a broad phrase like "search Figma for checkout designs", ask for a Figma link, file key, project/file name, team/library, or design-system scope before delegating. Use `whoami` only as a connectivity check; it does not prove access to a specific file.

## Quick Command

Run `claude -p` from a trusted working directory. Use `--setting-sources project,local` so delegated Figma inspections do not inherit user-level hooks that can add interactive follow-up instructions to machine-readable connector output. Do not use `--bare`, `--safe-mode`, `--disable-slash-commands`, or `--strict-mcp-config` because those can hide configured connectors.

```bash
prompt='You are a read-only Figma connector delegate. Use configured Figma connector tools only. Do not create files, edit designs, upload assets, export videos, send code-connect mappings, generate diagrams, comment, publish, or make any external changes. Task: <describe the Figma file/node/design-system request>. Return concise Markdown with: Summary; exact Figma file/page/node identifiers or URLs when available; findings from metadata/design context/screenshots/variables/libraries/design-system search; and connector/access limitations.'
claude -p --setting-sources project,local --output-format json --no-session-persistence --max-budget-usd 1 --allowedTools "mcp__claude_ai_Figma__whoami,mcp__claude_ai_Figma__get_design_context,mcp__claude_ai_Figma__get_metadata,mcp__claude_ai_Figma__get_screenshot,mcp__claude_ai_Figma__get_variable_defs,mcp__claude_ai_Figma__get_motion_context,mcp__claude_ai_Figma__get_figjam,mcp__claude_ai_Figma__get_libraries,mcp__claude_ai_Figma__search_design_system,mcp__claude_ai_Figma__get_code_connect_map,mcp__claude_ai_Figma__get_code_connect_suggestions,mcp__claude_ai_Figma__get_context_for_code_connect,mcp__claude_ai_Figma__list_shader_effects,mcp__claude_ai_Figma__get_shader_effect,mcp__claude_ai_Figma__list_shader_fills,mcp__claude_ai_Figma__get_shader_fill" -- "$prompt" < /dev/null
```

Read the JSON `result` field as the delegated answer. Also inspect `permission_denials`: if a read-only Figma tool was denied, rerun once with that exact read-only tool name in `--allowedTools`. Do not allow broad tool patterns or write-capable Figma tools.

Keep `--setting-sources project,local` on delegated commands unless you have verified the user's hooks are safe for nested, non-interactive runs. User-level Stop hooks can turn an otherwise successful connector result into a second model turn, which may pollute or replace the JSON `result`.

Keep the `--` before the prompt because `--allowedTools` is variadic and otherwise consumes the prompt as another tool name.

## Search Workflow

1. Identify the Figma scope: URL, file key, node ID, page/frame name, team/library, or design-system file.
2. If scope is missing, ask for it instead of claiming a global Figma search.
3. Choose the smallest read-only tool set for the request:
   - `whoami` for connector/auth connectivity.
   - `get_metadata` for file/page/node inventory.
   - `get_design_context` for selected frames/components/layout context.
   - `get_screenshot` only when visual inspection is needed.
   - `get_variable_defs` and `get_libraries` for tokens/libraries.
   - `search_design_system` for design-system assets within a known file scope.
   - Code-connect and shader read tools only when those domains are relevant.
4. Ask the delegate to cite Figma file/page/node identifiers and state access gaps clearly.
5. Summarize in the current conversation without persisting screenshots or private design data unless the user explicitly asks for an artifact.

## Prompt Templates

### File Or Node Inspection

```text
Use the configured Figma connector only. Inspect this Figma URL/file/node: <url-or-fileKey-nodeId>.
Return file/page/node identifiers, relevant metadata, design context, and access limitations.
Do not edit, comment, export, or publish.
```

### Visual Review

```text
Use the configured Figma connector only. Review the screenshot/design context for: <url-or-fileKey-nodeId>.
Return concise visual observations with the file/page/frame identifiers used.
Do not export video, upload assets, edit, comment, or publish.
```

### Design System Lookup

```text
Use the configured Figma connector only. In this known design-system file/scope: <fileKey-or-url>, search for: <component/variable/style>.
Return matching components, variables, styles, libraries, and URLs/IDs when available.
Do not edit libraries or send code-connect mappings.
```

## Failure Cases

If `claude` is not installed, not authenticated, lacks Figma connector access, or the connector returns no usable citations, stop and report that blocker.

If the request lacks a Figma URL/file key/node ID and cannot be answered from a known design-system scope, ask for scope rather than delegating a fake global search.
