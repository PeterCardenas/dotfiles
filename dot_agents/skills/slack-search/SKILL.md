---
name: slack-search
description: Use this skill for requests to search Slack messages or channels, inspect Slack attachments, or download a specific Slack file through a configured connector. It delegates read-only Slack access with `slack-search`, reports cited message evidence, and can save an explicitly requested attachment locally for inspection.
---

# Slack Search

Use this skill when the current agent needs Slack messages, channel information, or attachment content that is available through a configured connector but not through the current runtime's tools. Delegate Slack reads with `slack-search`, then synthesize the returned evidence or inspect the explicitly downloaded local file.

## Safety Model

Keep Slack operations read-only. The delegated run may search messages or download an attachment the user explicitly requested, but it must not send messages, add reactions, notify people, or change Slack state.

Downloading writes external content to the local filesystem. Require an explicit file ID and output path, do not extract or execute the file automatically, and verify its signature, size, and SHA-256 first. Never reply to other people's Slack messages.

## Command

Search:

```bash
slack-search "<query, channel, user, date range, customer/account, or exact phrase>"
```

Download a known attachment after the user asks for it:

```bash
slack-search --download-file <Slack file ID> --output <local path>
```

Read the JSON `result` field as the delegated answer. Download mode reads the file bytes straight from the raw `slack_read_file` tool result in the delegate's event stream (a saved blob path, or an inline `image`/`document` block); it never asks the model to transcribe a path or base64, so images, PDFs, and archives all go through the same path, and parallel downloads are safe. It does not grant the delegate shell or file-writing tools. If the required read-only Slack tool is denied, report the exact denial rather than substituting broader permissions.

The download result includes `source` (`blob` or `inline`) and `mime_type`. If it includes `note`, the file arrived as an inline image and may be downscaled or re-encoded: use it for visual inspection, but don't treat it as the original's bytes or resolution.

## Workflow

1. Clarify scope only when the request is ambiguous enough to risk a broad or sensitive search. Useful constraints are channel, user, date range, customer/account, incident name, and exact phrase.
2. Search both public and private channels when looking for messages. Resolve channel/workspace visibility first when the user asks about a channel name.
3. Request source-specific evidence: channel name, author, date, permalink or thread link when available, and a short quoted snippet.
4. When a result identifies a relevant attachment, report its file ID, filename, type, size, and permalink. Do not claim to know archive contents from metadata alone.
5. If the user asks to download it, use download mode with a path under `temp/` unless they provided another path. Verify the downloaded file before inspecting it; list archive entries before extracting, and extract only when needed into a dedicated temporary directory.
6. Summarize minimally if results contain private or sensitive data. Do not persist Slack excerpts or attachments unless the user explicitly asks.

## Failure Cases

If `slack-search` is not installed, authentication is missing, connector access is unavailable, or download mode returns no verified file, stop and report that blocker along with the exact stderr. Download errors name the cause (tool error text, block types returned, or missing `slack_read_file` call), so do not retry the same file ID blindly or switch to asking the delegate to "describe" the file as a substitute for downloading it. Do not pretend to have searched or downloaded through another path.
