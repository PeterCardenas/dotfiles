---
name: slack-search
description: Use this skill for requests to search Slack messages or channels through a configured Slack connector. It delegates read-only Slack searches with `slack-search` and reports channels, message dates/authors, permalinks, snippets, and access limits.
---

# Slack Search

Use this skill when the current agent needs Slack message or channel information that is available through a configured connector but not through the current runtime's tools. Delegate read-only Slack search with `slack-search`, then synthesize the returned evidence in the current conversation.

## Safety Model

Keep connector work read-only. The delegated run may search and read Slack messages, threads, channels, and related metadata, but it should not send messages, add reactions, notify people, or make external changes.

If the user asks for a write action, do the search first and ask for explicit confirmation before any external write. Never reply to other people's Slack messages unless the user explicitly confirms the exact message.

## Command

```bash
slack-search "<query, channel, user, date range, customer/account, or exact phrase>"
```

Read the JSON `result` field as the delegated answer. Also inspect `permission_denials`: if a read-only Slack search tool was denied, rerun only after the exact read-only tool is approved. Do not use broad tool patterns or write-capable connector tools.

## Workflow

1. Clarify scope only when the request is ambiguous enough to risk a broad or sensitive search. Useful constraints are channel, user, date range, customer/account, incident name, and exact phrase.
2. Search both public and private channels when looking for messages. Resolve channel/workspace visibility first when the user asks about a channel name.
3. Request source-specific evidence: channel name, author, date, permalink or thread link when available, and a short quoted snippet.
4. Summarize minimally if results contain private or sensitive data. Do not persist Slack excerpts into files unless the user explicitly asks for an artifact.

## Failure Cases

If `slack-search` is not installed, authentication is missing, connector access is unavailable, or the connector returns no usable citations, stop and report that blocker. Do not pretend to have searched Slack through another path.
