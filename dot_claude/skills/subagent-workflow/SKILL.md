---
name: subagent-workflow
description: Use for tasks with meaningful complexity, such as multi-step implementation, work spanning multiple files or components, or work needing independent validation and review; also use when the user explicitly requests /subagent-workflow or subagents. Keep simple tasks direct. Orchestrate the complex work in context-isolated children.
---

# Subagent Workflow

- The user's standing preference authorizes delegation for meaningfully complex tasks, even without an explicit /subagent-workflow request. Keep simple tasks direct. Once invoked, do task execution in subagents; the parent scopes, routes, arbitrates, verifies evidence, and synthesizes results without taking over child-owned implementation.
- Use the smallest useful set of focused subagents. Research and planning are conditional on what the task needs, not mandatory stages.
- Give each subagent the necessary context, repo/cwd/ref, edit boundary, deliverable, checks, and stop conditions; do not grant nested delegation by default.
- Parallelize only independent scopes, with one writer per cwd/worktree; otherwise run sequentially. Resume a child only for same-task follow-ups.
- For Pi, read the `pi-subagents` guidance and list executable agents before launch. An authorized multi-step workflow uses one top-level async `subagent` workflow call with child steps inside it; bind durable output on child runs. Use the model and thinking defaults from Pi settings unless the user requests an override; check `action: "models"` before overriding. Yield for native async completion; do not poll or use `bg_wait` just to wait for an ordinary child. Treat child/tool/launch failures as infrastructure blockers, not permission to switch to a different execution mode.
- Treat validation and independent adversarial review as required gates for implementation work in this workflow. Keep them separate from the writer and resolve findings before completion; for read-only advice, use only the checks that answer the request.
- For implementation, the validation subagent must run the most relevant real workflow or test command, record the exact command and outcome, and identify pre-existing failures separately from regressions.
- For implementation, a fresh-context read-only reviewer must independently inspect the resulting diff, tests, and assumptions for correctness, regressions, scope creep, and missing coverage; it must return explicit findings or state that none were found.
- Do not report implementation complete until both gates have returned. The parent must verify their results, resolve findings through the owning child, and rerun validation and review when fixes are made.

- **Verify the requested outcome at its real boundary.** Do not mark work complete until the requested result has been directly verified: rendered preview for UI work, consumed artifact for build/package work, actual API response for API work, deployed target for deployment work, and merge/release state for delivery work.

- **Proxy checks are not completion evidence.** Source inspection, typechecks, package-resolution checks, local smoke tests, route availability, status badges, and file existence are proxy evidence only. State exactly what they establish and what primary outcome remains unverified.

- **A blocker makes the task blocked.** If a required validation, authentication step, environment prerequisite, deploy, merge gate, or requested artifact remains failed, unavailable, or contradictory, report the task as `Blocked` or `Unverified`—not complete. Do not proceed with polish or adjacent work unless the user accepts the partial result.

- **Validate before durable external actions.** Before pushing, updating a PR, uploading evidence, deploying, publishing, or modifying shared configuration, run the strongest available validation and inspect the result. If direct validation cannot be performed, stop and ask before making the external change.

- **Validate artifacts, not metadata.** For browser evidence, inspect the rendered preview for errors and expected state, then inspect a frame from every saved recording before upload. For builds, inspect the emitted artifact or consuming application—not only source or intermediate package output.

- **Final reports must separate confidence levels.** Use `Verified`, `Unverified`, and `Blocked` headings. Only put claims supported by direct evidence in `Verified`; include the exact command/check and outcome.

- **Stop on contradiction.** If logs, agents, artifacts, or checks disagree, stop treating the work as validated. Resolve the contradiction at the actual product boundary before editing reports, PR descriptions, or evidence summaries.
