## Practical Instructions

1. Run relevant tests before requesting review, and report results.
2. Do not introduce `any` or unnecessary type casts.
3. Model null/undefined explicitly; do not hide invalid states.
4. Reuse existing shared helpers/hooks before adding new abstractions.
5. Rename unclear symbols until behavior is obvious from names.
6. Add concise "why" comments for non-obvious logic.
7. Remove unused code/config/dependencies in the same change.
8. Keep each PR scoped to one concern; split unrelated edits.
9. Keep style and patterns consistent with nearby code.
10. Validate dependency/version changes against project policy.
11. Use canonical config locations; avoid one-off config files.
12. Prefer tool-native APIs over ad-hoc scripts when equivalent.
13. State API compatibility impact when changing contracts.
14. Add a regression test for each bug fix when feasible.

## Philosophical Instructions

1. Optimize for long-term clarity over short-term speed.
2. Treat type safety as design, not friction.
3. Prefer evidence (tests) over confidence statements.
4. Keep codebases coherent by converging on shared primitives.
5. Minimize cognitive load with small, focused, readable diffs.
6. Make failure modes explicit and deterministic.
7. Prefer deletion over preserving speculative complexity.
8. Keep boundaries intentional; avoid accidental coupling.
9. Favor boring, maintainable tooling choices.
10. Document decisions where future readers may disagree.

## Mechanical Instructions

1. Before review request, run targeted tests and paste command + outcome.
2. Scan diff for `any`, `as any`, and avoidable casts; eliminate them.
3. Check nullable/optional paths; enforce invariants at boundaries.
4. Search for an existing helper/hook before creating a new utility.
5. Perform a naming pass: ambiguous identifiers must be renamed.
6. Remove dead code/config flags introduced or exposed by the change.
7. Verify PR scope: if two concerns exist, split into separate PRs.
8. Run formatter/lint and resolve style drift to local conventions.
9. Check dependency and lockfile changes for policy compliance.
10. Confirm config edits are in canonical files/locations.
11. For API changes, add a compatibility note in PR description.
12. For bug fixes, add or update at least one regression test/check.

## Prioritized Top-12 Blended Rules

1. Run relevant tests before review; include evidence.
2. Eliminate `any` and unnecessary casts.
3. Handle null/undefined/invalid states explicitly and fail fast.
4. Reuse shared helpers/hooks before creating new abstractions.
5. Rename unclear identifiers to make intent obvious.
6. Add concise "why" comments for non-obvious behavior.
7. Remove unused code/config/dependencies immediately.
8. Keep PR scope to one concern; split unrelated work.
9. Enforce local style/consistency before submit.
10. Validate dependency/version changes against policy.
11. Keep configuration in canonical locations only.
12. Add regression coverage for bug fixes when practical.
