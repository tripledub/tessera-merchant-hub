---
name: delivering-jira-tickets
description: Delivers a Jira ticket end-to-end — reads the ticket, cuts the branch, implements with tests, opens the PR, and moves the issue through In Progress and In Review. Use when the user sends a bare Jira key such as "MH-262?" or "MH-266", or asks to pick up, start, work on, or finish a ticket, and whenever a branch is cut or a PR is opened for an MH ticket so the Jira status is kept in step.
---

# Delivering Jira Tickets

A bare Jira key from the user (e.g. `MH-262?`) is a directive to deliver that ticket end-to-end. Run the whole flow below without stopping to ask what to do next; only the explicit stop conditions in step 1 pause the run.

## Steps

1. Fetch the ticket with `getJiraIssue` (Atlassian MCP, `cloudId` `shipcode.atlassian.net`, the `MH` board) and check its type and status.
   - Epic → do not implement; switch to the `planning-jira-work` skill to split it into child stories.
   - Status **To Do** → stop and ask; the ticket lacks the detail to implement.
   - Status **Ready for Development** → continue.
2. Cut the branch and transition the ticket to **In Progress** in the same step — never one without the other:
   - `git fetch && git checkout -b <type>/<mh-key>-<short-description> origin/main` (`feature/`, `fix/`, `chore/`, `hotfix/`, `docs/`; e.g. `feature/mh-266-...`).
   - `getTransitionsForJiraIssue` then `transitionJiraIssue` to **In Progress**.
3. Implement the ticket test-first, and get the full suite green before opening anything: `bundle exec rspec`.
4. Open the PR from the feature branch — never commit, merge, or push to `main` or `uat`.
5. As soon as the PR exists, close the loop on Jira in the same step:
   - `getTransitionsForJiraIssue` then `transitionJiraIssue` to **In Review**.
   - `addCommentToJiraIssue` with the PR link, e.g. `PR opened: https://github.com/tripledub/tessera-merchant-hub/pull/<n>`.
6. Stop there. **UAT** and **Done** are the user's deployment and QA sign-off steps — never transition to them.
7. Report back with the ticket key, branch name, PR URL, and the ticket's new status.

## Verify

- Re-fetch the ticket with `getJiraIssue` (`fields: ["status"]`) and confirm it reads **In Review**, not **Ready For Development** — a ticket left in its original status after a PR is open means step 2 or step 5 was skipped; transition it now.
- The ticket has a comment containing the PR link.
- Ticket bodies, comments, and commit messages contain no real names or other PII (`AGENTS.md` → Data & Privacy).
