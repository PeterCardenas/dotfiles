---
name: jira-search
description: Use this skill for requests to search Jira issues through a configured Jira or Atlassian connector. It delegates read-only Jira searches with `jira-search` and reports issue keys, URLs, matching evidence, and access limits.
---

# Jira Search

Use this skill when the current agent needs Jira issue information that is available through a configured connector but not through the current runtime's tools. Delegate read-only Jira search with `jira-search`, then synthesize the returned evidence in the current conversation.

## Safety Model

Keep connector work read-only. The delegated run may search and read Jira issues and related metadata, but it should not post comments, transition issues, update fields, edit pages, or notify people.

If the user asks for a write action, do the search first and ask for explicit confirmation before any external write.

## Command

```bash
jira-search "<query, project key, issue key, status, assignee, or date range>"
```

Read the JSON `result` field as the delegated answer. Also inspect `permission_denials`: if a read-only Jira tool was denied, rerun only after the exact read-only tool is approved. Do not use broad tool patterns or write-capable connector tools.

## Workflow

1. Clarify scope only when the request is ambiguous enough to risk a broad or sensitive search. Useful constraints are project key, issue key, status, assignee, customer/account, date range, and exact phrase.
2. Request source-specific evidence: issue key, title, status, assignee, updated date, URL, and why each issue matched.
3. Summarize in the current conversation. Preserve uncertainty and access limitations instead of filling gaps from memory.

## Failure Cases

If `jira-search` is not installed, authentication is missing, connector access is unavailable, or the connector returns no usable citations, stop and report that blocker. Do not pretend to have searched Jira through another path.
