---
name: claude-connector-search
description: Use this skill for any request to search Jira issues, Confluence pages/docs, or Slack messages through Claude connectors. It delegates read-only connector searches to `claude -p` and reports cited results or access limits.
---

# Claude Connector Search

Use this skill when the current agent needs Jira, Confluence, or Slack information that is available through Claude Code connectors but not through the current runtime's tools. The pattern is: delegate the source-specific search to `claude -p`, then synthesize the returned evidence for the user in the current conversation.

## Safety Model

Keep connector work read-only. The delegated Claude run may search and read Jira issues, Confluence pages, Slack messages, threads, channels, and related metadata, but it should not post, comment, transition issues, update fields, edit pages, add reactions, or notify people.

If the user asks for a write action, do the search first and ask for explicit confirmation before any external write. If the user did not ask for Jira, Confluence, or Slack specifically, prefer the current runtime's local tools before invoking another Claude process.

## Quick Command

Run `claude -p` from a trusted working directory. Do not use `--bare`, `--safe-mode`, `--disable-slash-commands`, or `--strict-mcp-config` because those can hide configured connectors.

```bash
prompt='You are a read-only enterprise search delegate. Use the configured Jira, Confluence, and Slack connectors if they are available. Do not use web search as a substitute. Do not post messages, add comments, transition issues, update fields, edit pages, or make any external changes. Task: <describe the user search request>. Return concise Markdown with: Summary; Jira findings with issue keys/status/assignees and URLs when available; Confluence findings with page titles/spaces and URLs when available; Slack findings with channel names, message dates/authors, thread links or permalinks when available; gaps or connector/access limitations.'
claude -p --output-format json --no-session-persistence --max-budget-usd 1 --allowedTools "mcp__claude_ai_Atlassian__search,mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql,mcp__claude_ai_Slack__slack_search_public,mcp__claude_ai_Slack__slack_search_public_and_private,mcp__claude_ai_Slack__slack_search_channels" -- "$prompt" < /dev/null
```

Read the JSON `result` field as the delegated answer. Also inspect `permission_denials`: if a read-only Jira or Slack search tool was denied, rerun once with that exact read-only tool name in `--allowedTools`. Do not allow broad tool patterns or write-capable connector tools.

If the CLI exits non-zero, report the error and whether it looks like missing auth, missing connector access, or an ambiguous query.

## Search Workflow

1. Clarify scope only when the request is ambiguous enough to risk a broad or sensitive search. Useful constraints are project key, Jira issue key, Confluence space, Slack channel, user, date range, customer/account name, and exact phrase.
2. Choose one delegated run for tightly coupled Jira and Slack questions, or separate runs when the sources are independent. Separate runs usually produce cleaner evidence.
3. Ask the delegate to use connectors by name and to say explicitly when a connector is unavailable. This prevents hallucinated search results.
4. Request source-specific evidence: Jira issue keys and URLs; Confluence page titles/spaces and URLs; Slack channel names, dates, authors, and permalinks.
5. Summarize in the current conversation. Preserve uncertainty and access limitations instead of filling gaps from memory.

For headless runs, expect MCP connector permissions to require pre-approval. Prefer exact read-only tool names from a prior `permission_denials` entry, such as `mcp__claude_ai_Atlassian__search`, `mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql`, `mcp__claude_ai_Slack__slack_search_public`, `mcp__claude_ai_Slack__slack_search_public_and_private`, and `mcp__claude_ai_Slack__slack_search_channels`. If the connector exposes different read-only search tool names, use those exact names instead.

Use `slack_search_public_and_private` only when the user asks for private-channel coverage, complete Slack coverage, or a scope check that cannot be answered from public channels alone. Use `slack_search_channels` to resolve channel/workspace visibility before message search.

When another agent will execute the command, prefer the single-line prompt variable form above. It avoids nested heredocs being flattened or retried by shell wrappers. Keep the `--` before the prompt because `--allowedTools` is variadic and otherwise consumes the prompt as another tool name.

## Prompt Templates

### Jira Only

```text
Use the configured Jira connector only. Search for: <query>.
Constraints: <project/status/assignee/date range if known>.
Return issue key, title, status, assignee, updated date, URL, and why each issue matched.
Do not update Jira.
```

### Slack Only

```text
Use the configured Slack connector only. Search for: <query>.
Constraints: <channels/users/date range if known>.
Return channel, author, date, permalink/thread link when available, and a short quoted snippet.
Do not send messages or reactions.
```

### Confluence Only

```text
Use the configured Confluence or Atlassian connector only. Search for: <query>.
Constraints: <space/title/date range if known>.
Return page title, space, last updated date when available, URL, and why each page matched.
Do not edit pages or add comments.
```

### Jira, Confluence, And Slack Correlation

```text
Use the configured Jira, Confluence, and Slack connectors. Find Jira issues, Confluence pages, and Slack discussions related to: <query>.
Correlate only when there is explicit overlap such as an issue key, shared incident name, customer/account, linked URL, or matching phrase.
Return a concise table of correlated evidence and a separate section for uncorrelated but relevant findings.
Do not make external changes.
```

## Handling Results

Treat connector output as evidence, not as final reasoning. In your response:

- Lead with the answer the user asked for.
- Include links or stable IDs for every important claim when the delegate provided them.
- Distinguish "no results found" from "connector unavailable" and "access denied".
- Avoid copying long Slack excerpts. Use short snippets and links.
- If results contain private or sensitive data, summarize minimally and do not persist them into files unless the user explicitly asked for an artifact.

## Failure Cases

If `claude` is not installed, not authenticated, lacks connector access, or the connectors return no usable citations, stop and report that blocker. Do not pretend to have searched Jira or Slack through another path.

If the query might expose sensitive people data or broad private communications, narrow the search before running it. Good narrowing questions include "which project or channel?", "what date range?", and "which customer or incident name?".
