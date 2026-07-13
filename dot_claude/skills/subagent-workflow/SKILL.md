---
name: subagent-workflow
description: Orchestrates substantial work across context-isolated subagents.
---

# Subagent Workflow

- Default to direct work; use the smallest useful set of focused subagents.
- Stage substantial work as research → plan → implement → validate → adversarial review.
- Give each subagent the necessary context, constraints, artifacts, and deliverable; tell it not to delegate further.
- Parallelize only independent scopes; otherwise run sequentially.
- Resume only for same-task follow-ups, verify and synthesize results, and iterate fixes with relevant real-workflow or CI checks until green.
