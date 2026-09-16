---
name: planning-jira-work
description: Plans and files work in Jira before any code is written — grooms thin or unclear tickets point by point with the user, splits epics into child stories, captures newly discovered bugs or feature ideas as new tickets before any fix begins, and triages pasted bug reports or error logs into the right existing ticket. Use when a Jira key or epic is mentioned, when the user says "can we groom this ticket", "can we discuss first", "I don't fully understand the requirements", "we need stories", "need a new ticket", "maybe even an epic", when asked to pick up, design, or implement a ticket, when the user pastes an error message, log excerpt, or bug report, and — above all — the moment a bug or improvement is noticed mid-session or the user says "can you file a bug I found as a ticket before fixing it", "file this as a ticket", "raise a ticket for this", "before fixing it", or "think there is a regression here from a previous fix".
---

# Planning Jira Work

Jira is the unit of planning in this project: nothing is designed or built until it exists as a workable Jira story.

## Steps

1. Before designing or implementing anything, fetch the issue and check its type with `getJiraIssue` (Atlassian MCP, the `MH` board).
2. **If it is an epic, stop — an epic is never one unit of work.** Propose a breakdown into child stories, get the user's agreement on the split, then create each one with `createJiraIssue` (issue type `Story`, `parent` set to the epic key). Design and implement one story at a time.
3. **Groom before building** when the user asks to groom or discuss a ticket, or when the description is thin — no acceptance criteria, no note of current behaviour, no edge cases. A status of **Ready For Development** does not exempt a ticket from this.
   1. Ground the discussion in the real current state first: read the controllers, models, views, services, and specs the ticket touches (delegate a wide flow to a research subagent) and any project skill the ticket names, before proposing anything. Grooming from the ticket text alone produces guesses.
   2. Walk the ticket **point by point**, one requirement per exchange. For each, give: what the code does today with `path/to/file.rb:line`, whether the requirement is already satisfied by it, and the open question or judgment call it leaves. Ask the user to confirm each point before moving to the next.
   3. Name the judgment calls explicitly rather than deciding silently — list the options with their tradeoffs and recommend one. Use `AskUserQuestion` when the choice changes the ticket's scope.
   4. Only once the user has agreed the scope, write it back with `editJiraIssue` — a description with concrete acceptance criteria plus a note of what is already in place. If the ticket was **To Do**, `getTransitionsForJiraIssue` then `transitionJiraIssue` to **Ready For Development**.
   5. Stop there and wait for the user to say the ticket is ready to pick up. Grooming never rolls straight into a branch or an implementation.
4. If it is a story, confirm its status is **Ready for Development** before starting — see the Jira Workflow section of `AGENTS.md` for the status ladder.
5. When a bug or feature idea surfaces mid-session — whether the user reports it or you notice it while working on something else — **file the Jira ticket before any fix work begins**: no branch, no edit, no diagnosis that quietly turns into a patch. Create it with `createJiraIssue` on the `MH` board (issue type `Bug` for a defect, `Story` for an improvement); ask which project and issue type only if that is genuinely unclear. If the user suspects a regression from a previous fix, run the triage in step 6 first to decide between a new linked ticket and reopening the old one. A large idea may itself be an epic, in which case return to step 2 and split it. Report the new key and wait for the user to say whether to pick it up now — "file it" is not "fix it".
6. For a pasted bug report, error message, or log excerpt, triage into Jira rather than jumping to a fix:
   1. Search for duplicates and prior fixes with `searchJiraIssuesUsingJql` on summary/description keywords.
   2. For any candidate already marked **Done**, verify the fix actually shipped: `git log --oneline --all --grep '<MH-key>'`, plus `git log <path/to/file>` on the files its acceptance criteria cover. A ticket closed by an unrelated commit is a mislink, not a fix.
   3. Present the options with `AskUserQuestion` — reopen the existing ticket, create a new ticket linked to it as a regression, or comment only — and recommend one.
   4. Apply the choice: `addCommentToJiraIssue` with the root cause, today's reproduction, and the log excerpt; then `getTransitionsForJiraIssue` and `transitionJiraIssue` to **Ready For Development** when reopening.
7. Change no application code during grooming, triage, or decomposition. Report the Jira outcome and wait for the user to say which ticket to pick up.

## Verify

- A groomed ticket's description carries acceptance criteria the user explicitly agreed to, and no application code changed in that pass.
- Every bug or idea surfaced this session has a Jira key, and any epic has child stories covering it.
- No application code changed between a bug being noticed and its ticket existing — the ticket key was reported before the first edit.
- Ticket bodies and comments contain no real names or other PII (`AGENTS.md` → Data & Privacy).
- After a triage-only session, `git status` shows a clean working tree.
