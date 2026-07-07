---
name: confluence-search
description: Use this skill for requests to search Confluence pages or docs through a configured Confluence or Atlassian connector. It delegates read-only Confluence searches with `confluence-search` and reports page titles, URLs, matching evidence, and access limits.
---

# Confluence Search

Use this skill when the current agent needs Confluence page or documentation information that is available through a configured connector but not through the current runtime's tools. Delegate read-only Confluence search with `confluence-search`, then synthesize the returned evidence in the current conversation.

## Safety Model

Keep connector work read-only. The delegated run may search and read Confluence pages, spaces, and metadata, but it should not edit pages, add comments, update Jira, publish content, or notify people.

If the user asks for a write action, do the search first and ask for explicit confirmation before any external write.

## Command

```bash
confluence-search "<query, space, title, owner, date range, or exact phrase>"
```

Read the JSON `result` field as the delegated answer. Also inspect `permission_denials`: if a read-only Confluence or Atlassian search tool was denied, rerun only after the exact read-only tool is approved. Do not use broad tool patterns or write-capable connector tools.

## Workflow

1. Clarify scope only when the request is ambiguous enough to risk a broad or sensitive search. Useful constraints are space, page title, owner, customer/account, date range, and exact phrase.
2. Request source-specific evidence: page title, space, last updated date, URL, and why each page matched.
3. Summarize in the current conversation. Preserve uncertainty and access limitations instead of filling gaps from memory.

## Failure Cases

If `confluence-search` is not installed, authentication is missing, connector access is unavailable, or the connector returns no usable citations, stop and report that blocker. Do not pretend to have searched Confluence through another path.
