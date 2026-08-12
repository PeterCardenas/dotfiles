---
name: subagent-workflow
description: Orchestrates substantial work by requiring all task execution to happen in context-isolated subagents.
---

# Subagent Workflow

- Do all task execution in subagents. The parent agent only scopes, launches, resumes, verifies, and synthesizes subagent work.
- Use the smallest useful set of focused subagents.
- Stage substantial work as research → plan → implement → validate → adversarial review.
- Give each subagent the necessary context, artifacts, and deliverable; tell it not to delegate further.
- Parallelize only independent scopes; otherwise run sequentially.
- Resume only for same-task follow-ups, verify and synthesize results, and iterate fixes with relevant real-workflow or CI checks until green.
- Treat `validate` and `adversarial review` as mandatory gates, not optional phases.
- The validation subagent must run the most relevant real workflow or test command, record the exact command and outcome, and identify pre-existing failures separately from regressions.
- The adversarial-review subagent must independently inspect the resulting diff, tests, and stated assumptions for correctness, regressions, scope creep, and missing coverage; it must return explicit findings or state that none were found.
- Do not report the task complete until both gates have returned. The parent must verify their results, resolve findings, and rerun validation and review when fixes are made.

- **Verify the requested outcome at its real boundary.** Do not mark work complete until the requested result has been directly verified: rendered preview for UI work, consumed artifact for build/package work, actual API response for API work, deployed target for deployment work, and merge/release state for delivery work.

- **Proxy checks are not completion evidence.** Source inspection, typechecks, package-resolution checks, local smoke tests, route availability, status badges, and file existence are proxy evidence only. State exactly what they establish and what primary outcome remains unverified.

- **A blocker makes the task blocked.** If a required validation, authentication step, environment prerequisite, deploy, merge gate, or requested artifact remains failed, unavailable, or contradictory, report the task as `Blocked` or `Unverified`—not complete. Do not proceed with polish or adjacent work unless the user accepts the partial result.

- **Validate before durable external actions.** Before pushing, updating a PR, uploading evidence, deploying, publishing, or modifying shared configuration, run the strongest available validation and inspect the result. If direct validation cannot be performed, stop and ask before making the external change.

- **Validate artifacts, not metadata.** For browser evidence, inspect the rendered preview for errors and expected state, then inspect a frame from every saved recording before upload. For builds, inspect the emitted artifact or consuming application—not only source or intermediate package output.

- **Final reports must separate confidence levels.** Use `Verified`, `Unverified`, and `Blocked` headings. Only put claims supported by direct evidence in `Verified`; include the exact command/check and outcome.

- **Stop on contradiction.** If logs, agents, artifacts, or checks disagree, stop treating the work as validated. Resolve the contradiction at the actual product boundary before editing reports, PR descriptions, or evidence summaries.
