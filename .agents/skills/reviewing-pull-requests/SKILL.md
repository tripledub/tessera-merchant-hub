---
name: reviewing-pull-requests
description: Reviews a GitHub pull request through the engineering-code-reviewer subagent, posts concise inline comments on the PR itself, and on a recheck re-verifies every previously flagged finding one by one against the new head commit. Use whenever the user asks to review a PR or wants feedback on one, sends a PR URL, PR number, or ticket key, says "review this PR", "give any feedback inline where necessary", or "using the same pattern as above"; and on every recheck — "Have pushed some changes, please recheck", "Updated, please check again and comment if needed", "pushed a fix", "recheck", "check again" — or when the engineering_code_review task is invoked again after findings were already reported. The same delegate-and-comment-inline pattern applies to every follow-up PR and every follow-up round without being restated.
---

# Reviewing Pull Requests

PR review in this project is always delegated and always lands on the PR, not only in chat.

## Steps

1. Identify the PR from what the user gave you — a GitHub URL (e.g. `https://github.com/tripledub/tessera-merchant-hub/pull/234`), a bare PR number, or a ticket key such as `FR6482`. If no identifier is present at all, ask only for that. Never re-ask which subagent to use, whether to comment inline, or how deep to go — this skill is the answer.
2. Delegate the review to the `engineering-code-reviewer` subagent. Do not review the diff yourself and do not substitute a generic review agent.
3. Keep it read-only: review the exact base/head objects of the PR without checking out, switching, or otherwise changing the current branch or working tree.
4. Post the findings as inline comments on the PR, anchored to the file and line they concern — a chat-only write-up is not a delivered review. Use a pending review so the comments land together: `pull_request_review_write` with `method: "create"`, then `add_comment_to_pending_review` once per finding, then `pull_request_review_write` with `method: "submit_pending"`.
5. Keep every comment short — one to three sentences: what is wrong, its impact, and the concrete fix. Do not narrate review history, restate what the code and its specs already communicate, or explain general concepts.
6. In chat, report only: **Strengths**, then **Findings** ordered 🔴 blocking before 🟡 non-blocking — each with `path/to/file.rb:line`, **Impact**, and **Fix** — then a one-line **Merge verdict** (ready / not ready, and why).
7. When re-reviewing a PR you have already reviewed, follow the Re-review section below before listing anything new.
8. Don't grow the diff's own comments. Recommend keeping only non-obvious rationale (a line or two); failed earlier approaches and mechanics belong in the PR discussion or commit message, and test names plus assertions should document behaviour.

## Re-review (after fixes are pushed)

A recheck is not a fresh review. Every finding from the previous round comes back with an explicit status, decided from the updated code — never from the author's description of the fix.

1. Resolve the PR's new head commit and review against that immutable commit. If the shared workspace has acquired staged or unstaged local changes during the review, exclude them — they are not part of the PR.
2. Read the GitHub check runs for that head before concluding anything. A red job is part of the re-review result: do not report the pushed changes as complete while CI is failing, and name the failing job and the failing example.
3. List the previous round's findings, then verify each one **individually against the code at the new head** — read the changed files and their specs. Treat the author's summary of what they changed as a claim to test, not as evidence.
4. Give every prior finding one of three dispositions, each with the file and line that justifies it:
   - **Resolved** — the defect is gone and a test covers it.
   - **Partially resolved** — the production change is right but the test is weak, wrong, or failing (or vice versa). Say which half is still open.
   - **Unresolved** — the defect survives the fix. Explain the mechanism that defeats it.
5. Report new findings the fix itself introduced, listed separately from the prior-finding statuses.
6. Where findings were posted as GitHub threads: reply to the existing thread when the concern is unchanged, open a new inline comment when the update introduced a more specific defect, and say which threads are verified fixed and can now be resolved. Comment only where something is still actionable.
7. Close with a merge verdict — ready, ready with the listed fixes, or not ready — and the evidence behind it (checks, suite result, what you reproduced).

## Verify

- The findings are visible on the PR itself as inline comments, not only in the chat reply.
- `git status` is clean and the branch is unchanged — the review touched nothing.
- No single inline comment runs past a few sentences.
- On a recheck: every finding from the previous round appears in the output with a status — none silently dropped because the author said it was fixed — each citing the file/line or reproduction that decided it; CI status for the reviewed head is stated, including any failing job; new defects introduced by the fixes are listed separately; and only the pushed commit was reviewed, with no local staged changes leaking in.
- Comments and summary contain no real names or other PII (`AGENTS.md` → Data & Privacy).
