---
name: browser-preferences
description: Applies Peter's browser automation preferences alongside agent-browser. Use whenever a task needs website or Electron interaction, browser-based testing, browser screenshots, authentication, UI uploads, form submission, or any agent-browser workflow—even when the user does not explicitly request these preferences.
---

# Browser Preferences

Apply these instructions in addition to the current `agent-browser` workflow.

## Start with current guidance

Before the first `agent-browser` command, run `agent-browser skills get core`. Load a specialized `agent-browser` workflow only when its domain applies.

## Session continuity

If the task names an existing browser session, reuse that exact session. Preserve its authentication and its headed/headless mode; do not close, reset, replace, or change it unless the user asks.

For a new routine session, use headless mode. Use headed mode only when visual inspection, upload interaction, or interactive debugging needs it. Check Wayland compatibility before trying headed mode.

## Authentication

For login, SSO, consent, MFA, or an identity-provider redirect, invoke the `login-unblock` skill immediately and say that the authentication workflow is blocked on user action. Never retrieve, print, store, or hard-code credentials, and do not recreate an identity-provider flow manually. Resume and verify the same browser session after authentication.

## Evidence and external actions

For UI changes, validate the result in the running application. Capture focused before/after evidence when it materially demonstrates the result. Use the PR screenshot workflow when attaching that evidence to a pull request.

Before uploading files, submitting forms, publishing, sending messages, or otherwise mutating an external service, state the exact target and action, then obtain explicit confirmation. This keeps a request to prepare evidence separate from permission to share it externally.

## Handoff

Report the session used, verification performed, and any authentication blocker. Do not expose credentials or unrelated private browser content.
