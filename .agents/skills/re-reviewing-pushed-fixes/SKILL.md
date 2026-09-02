---
name: re-reviewing-pushed-fixes
description: Re-reviews a PR after the author pushes fixes — re-verifies every previously flagged finding one by one against the new head commit and reports each as resolved, partially resolved, or unresolved. Use when the user says "Have pushed some changes, please recheck", "Updated, please check again and comment if needed", "pushed a fix", "recheck", "check again", or re-invokes the code review after findings were already reported.
---

# Re-Reviewing Pushed Fixes

A recheck is not a fresh review. Every finding from the previous round must come back with an explicit status, verified from the updated code — never from the author's description of the fix.

## Steps

1. Resolve the new head commit of the PR and review against that immutable commit. If the shared workspace has acquired staged or unstaged local changes during the review, exclude them — they are not part of the PR.
2. Read the GitHub check runs for that head before concluding anything. A red test job is part of the re-review result: do not report the pushed changes as complete while CI is failing, and name the failing job and example.
3. List the previous round's findings explicitly, then verify each one **individually against the code at the new head** — read the changed files and their specs. Treat the author's summary of what they changed as a claim to test, not as evidence.
4. Give every prior finding one of three dispositions, with the file and line that justifies it:
   - **Resolved** — the defect is gone and a test covers it.
   - **Partially resolved** — the production change is right but the test is weak, wrong, or failing (or vice versa). Say which half is still open.
   - **Unresolved** — the defect survives the fix. Explain the mechanism that defeats it.
5. Report new findings the fix itself introduced, separately from the prior-finding statuses.
6. When findings were posted as GitHub threads: reply to the existing thread when the concern is unchanged, open a new inline comment when the update introduced a more specific defect, and state which threads are verified fixed and can now be resolved. Comment only where something is still actionable.
7. Close with a merge verdict — ready, ready with the listed fixes, or not ready — and the evidence behind it (checks, suite result, what you reproduced).

## Verify

- Every finding from the previous round appears in the output with a status; none is silently dropped because the author said it was fixed.
- Each status cites the file/line or the reproduction that proves it, not the push description.
- CI status for the reviewed head is stated, including any failing job.
- New defects introduced by the fixes are listed separately from prior-finding statuses.
- The review covered the pushed commit only — no local staged changes leaked into it.
