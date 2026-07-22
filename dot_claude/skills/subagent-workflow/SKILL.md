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
