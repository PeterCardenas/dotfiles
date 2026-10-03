---
name: browser-evidence
description: Capture and verify reviewable browser screenshots and screencasts. Use alongside agent-browser whenever taking, retaking, or handing off visual evidence of a UI, including PR demos and before/after comparisons. Not for simply inspecting existing PR images or uploading already-verified files.
---

# Browser evidence

Use `agent-browser` for browser actions and its current recording guidance (`agent-browser skills get core --full`). This skill handles evidence quality, not browser setup or PR uploads. Use `pr-add-screenshots` and `pr-image-visibility` when attaching evidence to a PR.

1. **Choose the proof.** Use screenshots for static states, short videos for interactions or motion. Identify what each capture should show, the exact page/state and build, and, for comparisons, the baseline and candidate under the same viewport and conditions. Do not use a motion-disabled still to rule out a motion change.
2. **Verify the source.** Inspect the rendered UI, not just the URL or page title. For Storybook, check the preview frame for the expected story and absence of errors. If demonstrating a built artifact, capture the built artifact rather than a dev server or mock. Fix failures before capturing; otherwise mark the case blocked.
3. **Rehearse, then capture.** Dry-run interactions, reset to the starting state, and record only the demonstration. Show the initial state, meaningful actions, and result with natural mouse movement and brief pauses; avoid blank starts and dead time. Keep screenshots focused without hiding essential context.
4. **Review the actual files.** Open every screenshot. Play each video or inspect frames from the beginning, transitions, and end; file existence and codec metadata do not prove its content. Check that the claimed behavior is visible, the UI is styled and unclipped, and no sensitive content is exposed. Retake bad captures. If the evidence contradicts the claim, investigate the source instead of changing the caption.
5. **Hand off clearly.** Provide a link or path per claim, a short caption saying what to look for, and `verified` or `blocked`. For a video, include a representative frame from that clip. Before calling shared evidence complete, confirm images render and videos play at the destination. Never call an artifact verified solely on a tool or subagent's summary.
