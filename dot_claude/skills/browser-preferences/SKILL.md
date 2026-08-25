---
name: browser-preferences
description: Applies Peter's CLI-first browser automation preferences alongside agent-browser. Use whenever a task may involve website or Electron interaction—including site operations that a CLI, API, MCP connector, or local tool might handle instead—or needs browser testing, screenshots, authentication, UI uploads, forms, or unattended polling that could launch browser auth. Do not use for ordinary read-only web research or tasks already constrained to a non-browser tool.
---

# Browser Preferences

Apply these instructions before and alongside the current `agent-browser` workflow.

## Prefer non-browser interfaces

Before opening a browser, check whether an official CLI, tool-native API, MCP connector, or local command can complete the task. Prefer that interface when it is equivalent: it is usually more deterministic and avoids UI, profile, and authentication side effects. A website name alone does not require a browser.

Use a browser when the task needs rendered visual state, UI-only interaction, browser-specific testing, or the user explicitly asks to use one. If the preferred interface fails, diagnose it rather than silently falling back to a browser.

Never launch or focus a browser as a side effect of polling, status checks, background refreshes, or other unattended work. Use cached state or a non-interactive interface instead.

## Start browser work with current guidance

Before the first `agent-browser` command, run `agent-browser skills get core`. Load a specialized `agent-browser` workflow only when its domain applies.

## Session continuity

Use headless mode. If the task names an existing browser session, reuse that exact session without changing it. Verify the target session or profile has the required access; a running browser process is not proof that it is authenticated.

## Authentication

Prefer the relevant CLI authentication flow when browser UI is unnecessary. For login, SSO, consent, MFA, or an identity-provider redirect in browser work, invoke the `login-unblock` skill immediately and say that the workflow is blocked on user action. Never retrieve, print, store, or hard-code credentials, recreate an identity-provider flow, or repeatedly retry challenges. Resume and verify the same session after authentication.

## Evidence and external actions

For UI changes, validate the result in the running application. Capture focused before/after evidence when it materially demonstrates the result. Use the PR screenshot workflow when attaching that evidence to a pull request.

Before uploading files, submitting forms, publishing, sending messages, or otherwise mutating an external service, state the exact target and action, then obtain explicit confirmation. After a mutation, verify persisted state, preferably by reading it back through a CLI or API.

## Handoff

Report the interface and session used, verification performed, and any authentication blocker. Do not expose credentials or unrelated private browser content.
