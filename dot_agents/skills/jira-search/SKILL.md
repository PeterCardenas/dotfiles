---
name: jira-search
description: Use this skill for requests to search Jira issues through a configured Jira or Atlassian connector. It delegates read-only Jira searches, including exporting issue descriptions from an epic or JQL result to a local Markdown file, and reports matching evidence and access limits.
---

# Jira Search

Use this skill when the current agent needs Jira issue information that is available through a configured connector but not through the current runtime's tools. Delegate read-only Jira search with `jira-search`, then synthesize the returned evidence in the current conversation or a requested local file.

## Safety Model

Keep connector work read-only. The delegated run may search and read Jira issues and related metadata, but it should not post comments, transition issues, update fields, edit pages, or notify people.

If the user asks for a write action, do the search first and ask for explicit confirmation before any external write.

## Command

```bash
jira-search "<query, project key, issue key, status, assignee, or date range>"
```

Read the JSON `result` field as the delegated answer. Also inspect `permission_denials`: if a read-only Jira tool was denied, rerun only after the exact read-only tool is approved. Do not use broad tool patterns or write-capable connector tools.

## Epic Description Exports

When the user asks to collect all descriptions beneath an epic:

1. Query the child issues with Jira search/JQL in a single read-only request, using `parent = <EPIC-KEY>` and the workspace's legacy epic-link field only when needed. Ask for the issue key, summary, description, status, and URL.
2. Explicitly tell the delegate to use the JQL search result, return every description verbatim in Markdown, and not call per-issue detail endpoints. This avoids an unnecessary permission prompt for `getJiraIssue` when search access is already sufficient.
3. If the result is too large, split the known issue keys into batches and make the same JQL-search-only request for each batch. Do not replace descriptions with summaries.
4. Create the requested local Markdown file only after every requested description was returned. Include a source link, one `## <KEY> — <summary>` section per issue, and the description body. Preserve empty descriptions as `_No description provided._`.
5. Verify completeness by comparing the exported issue-key count with the JQL result count. If any description cannot be read, do not create a partial file unless the user expressly requests one; report the missing keys and the exact denied read-only permission.

## Workflow

1. Clarify scope only when the request is ambiguous enough to risk a broad or sensitive search. Useful constraints are project key, issue key, status, assignee, customer/account, date range, and exact phrase.
2. Request source-specific evidence: issue key, title, status, assignee, updated date, URL, and why each issue matched.
3. For description exports, follow the Epic Description Exports workflow and report the saved local path and issue count.
4. Preserve uncertainty and access limitations instead of filling gaps from memory.

## Failure Cases

If `jira-search` is not installed, authentication is missing, connector access is unavailable, or the connector returns no usable citations, stop and report that blocker. Do not pretend to have searched Jira through another path.
