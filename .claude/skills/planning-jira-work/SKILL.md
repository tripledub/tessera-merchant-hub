---
name: planning-jira-work
description: Plans and files work in Jira before any code is written — splits epics into child stories, captures newly discovered bugs or feature ideas as new tickets, and triages pasted bug reports or error logs into the right existing ticket. Use when a Jira key or epic is mentioned, when asked to pick up, design, or implement a ticket, when the user says "we need stories", "need a new ticket", "maybe even an epic", or pastes an error message, log excerpt, or bug report, and whenever a bug or improvement is noticed mid-session.
---

# Planning Jira Work

Jira is the unit of planning in this project: nothing is designed or built until it exists as a workable Jira story.

## Steps

1. Before designing or implementing anything, fetch the issue and check its type with `getJiraIssue` (Atlassian MCP, the `MH` board).
2. **If it is an epic, stop — an epic is never one unit of work.** Propose a breakdown into child stories, get the user's agreement on the split, then create each one with `createJiraIssue` (issue type `Story`, `parent` set to the epic key). Design and implement one story at a time.
3. If it is a story, confirm its status is **Ready for Development** before starting — see the Jira Workflow section of `AGENTS.md` for the status ladder.
4. When a bug or feature idea surfaces mid-session — including one noticed while working on something else — file it as its own ticket before touching code. Ask which project and issue type if unclear; a large idea may itself be an epic, in which case return to step 2.
5. For a pasted bug report, error message, or log excerpt, triage into Jira rather than jumping to a fix:
   1. Search for duplicates and prior fixes with `searchJiraIssuesUsingJql` on summary/description keywords.
   2. For any candidate already marked **Done**, verify the fix actually shipped: `git log --oneline --all --grep '<MH-key>'`, plus `git log <path/to/file>` on the files its acceptance criteria cover. A ticket closed by an unrelated commit is a mislink, not a fix.
   3. Present the options with `AskUserQuestion` — reopen the existing ticket, create a new ticket linked to it as a regression, or comment only — and recommend one.
   4. Apply the choice: `addCommentToJiraIssue` with the root cause, today's reproduction, and the log excerpt; then `getTransitionsForJiraIssue` and `transitionJiraIssue` to **Ready For Development** when reopening.
6. Change no application code during triage or decomposition. Report the Jira outcome and wait for the user to say which ticket to pick up.

## Verify

- Every bug or idea surfaced this session has a Jira key, and any epic has child stories covering it.
- Ticket bodies and comments contain no real names or other PII (`AGENTS.md` → Data & Privacy).
- After a triage-only session, `git status` shows a clean working tree.
