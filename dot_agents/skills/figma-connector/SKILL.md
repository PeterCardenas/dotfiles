---
name: figma-connector
description: Use this skill for requests to inspect Figma files, designs, nodes, screenshots, variables, libraries, FigJam boards, or design-system assets through a configured Figma connector. It delegates read-only Figma inspection with `figma-inspect` and reports cited results or access limits.
---

# Figma Connector

Use this skill when the current agent needs Figma information that is available through a configured connector but not through the current runtime's tools. Delegate read-only Figma inspection with `figma-inspect`, then synthesize the returned evidence in the current conversation.

## Safety Model

Keep connector work read-only. The delegated run may inspect Figma file metadata, selected nodes, screenshots, variables, libraries, FigJam content, shader definitions, and design-system assets. It must not create files, edit designs, upload assets, export videos, send code-connect mappings, generate diagrams, comment, publish, or make any external change.

If the user asks for a Figma write/export action, first gather read-only context and ask for explicit confirmation before any write-capable workflow. Never upload local files or data to Figma without explicit user approval.

## Scope Requirements

Most Figma read tools require a concrete Figma file URL, file key, node ID, or existing file context. There is no generic full-text search across all Figma files/projects/comments in the current connector surface.

If the user gives only a broad phrase like "search Figma for checkout designs", ask for a Figma link, file key, project/file name, team/library, or design-system scope before delegating. Connectivity checks do not prove access to a specific file.

## Command

```bash
figma-inspect "<describe the Figma file/node/design-system request>"
```

Read the JSON `result` field as the delegated answer. Also inspect `permission_denials`: if a read-only Figma tool was denied, rerun only after the exact read-only tool is approved. Do not use broad tool patterns or write-capable Figma tools.

## Workflow

1. Identify the Figma scope: URL, file key, node ID, page/frame name, team/library, or design-system file.
2. If scope is missing, ask for it instead of claiming a global Figma search.
3. Ask for file/page/node identifiers and state access gaps clearly.
4. Summarize in the current conversation without persisting screenshots or private design data unless the user explicitly asks for an artifact.

## Failure Cases

If `figma-inspect` is not installed, authentication is missing, connector access is unavailable, or the connector returns no usable citations, stop and report that blocker.
