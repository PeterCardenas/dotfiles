---
name: pr-image-visibility
description: Use this whenever a task includes PR review, PR triage, release-readiness checks, UX validation, or risk assessment that depends on screenshots/images in GitHub PR descriptions or comments. This skill translates markdown image links (especially `github.com/user-attachments/...`) into rendered/private image URLs agents can fetch. Trigger even when image validation is only one step in a larger workflow. Always treat resolved private image URLs as ephemeral signed links that expire quickly.
---

# PR Image Visibility

Use this skill when an agent is reading PR text and needs to see embedded images that do not resolve from raw markdown links.

Primary target:

- Agents reviewing PR descriptions and PR comments.

Common symptom:

- Markdown includes `https://github.com/user-attachments/assets/...` links.
- The rendered page shows images, but raw markdown links do not reliably load for the agent.

## What this does

- Accepts a PR URL (`https://github.com/owner/repo/pull/123`) or `owner/repo` + PR number.
- Checks whether a given markdown image URL already resolves via HTTP HEAD.
- Queries GitHub GraphQL for PR body/comments/review comments.
- Extracts image URLs from markdown text and rendered HTML.
- Maps markdown image URLs to rendered HTML `src` URLs by positional order.
- Returns an explicit warning that resolved private URLs are ephemeral.

## Script

Use the bundled script:

- `scripts/resolve_pr_private_images.py`

## Usage

Resolve one URL from a PR:

```bash
python scripts/resolve_pr_private_images.py resolve \
  --pr-url 'https://github.com/OWNER/REPO/pull/123' \
  --src 'https://github.com/...'
```

Resolve one URL with JSON output and explicit gh user:

```bash
python scripts/resolve_pr_private_images.py resolve \
  --pr-url 'https://github.com/OWNER/REPO/pull/123' \
  --src 'https://github.com/...' \
  --gh-user 'peter-cardenas-ai' \
  --json
```

Build full mapping for a PR:

```bash
python scripts/resolve_pr_private_images.py map \
  --pr-url 'https://github.com/OWNER/REPO/pull/123' \
  --gh-user 'peter-cardenas-ai' \
  --json
```

Alternative input form:

```bash
python scripts/resolve_pr_private_images.py map \
  --repo 'OWNER/REPO' \
  --pr-number 123 \
  --gh-user 'peter-cardenas-ai' \
  --json
```

## Recommended agent workflow for PR descriptions

1. Read PR body/comments (for example via `gh pr view --json body,comments` or existing context).
2. Collect markdown image URLs (`github.com/user-attachments/...` and related GitHub image links).
3. Run this resolver to get rendered/private URLs.
4. Fetch image content immediately for analysis.
5. Do **not** persist resolved URLs in long-lived docs, test snapshots, or caches.

## Output expectations

- For `resolve`, return the resolved URL if available, otherwise empty output (or `null` in JSON mode).
- For `map`, return a JSON object keyed by markdown image URL with resolved HTML URL values.
- JSON output includes an `ephemeral_warning` field to remind agents the URLs are short-lived signed links.

## Notes

- If `GH_TOKEN` is set for a different account, pass `--gh-user` to force keyring auth user switching.
- Resolved `private-user-images.githubusercontent.com` links are signed and expire quickly. Use them immediately and expect refreshes to be needed.
