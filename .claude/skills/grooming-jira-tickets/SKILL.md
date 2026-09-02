---
name: grooming-jira-tickets
description: Runs a grounded, point-by-point grooming discussion on a Jira ticket before any implementation starts. Use when the user asks to groom or discuss a ticket, says something like "I don't fully understand the requirements", or a ticket is thin/ambiguous (no acceptance criteria, unclear current-vs-desired behavior) before picking it up.
---

# Grooming Underspecified Jira Tickets

A ticket with unclear requirements is not ready to implement, even if its status says otherwise. When the user asks to groom or discuss a ticket, or says they don't fully understand its requirements, run this procedure before writing any code.

## Steps

1. **Ground the discussion in research, not guesses.** Read the ticket, then pull up the current code/behavior it touches (and any relevant project skill reference, e.g. layered-rails/Archspec) before saying anything back to the user. Don't start asking questions purely from the ticket text.
2. **Confirm "already works" in the running app before you say it.** Reading the code is not enough to establish current behavior. For every point you are about to call already satisfied — or already broken — exercise it against the running app first: load the affected page (the `http://localhost:3000/...` URL the user is working from, or the equivalent record), perform the action with the same partial input the ticket describes, and report what you actually observed. If you cannot exercise it in this session, say "I haven't confirmed this at runtime" instead of asserting the behavior.
3. **Go point-by-point through the ticket's stated requirements.** For each point, state whether it's already satisfied by current behavior, a genuine bug, or genuinely new work — grounded in what steps 1–2 found, not assumption.
4. **Surface real judgment calls one at a time and wait for the answer** before moving to the next point. Don't dump the whole list of open questions in one message, and don't guess an answer yourself — each answer can change the scope of later points.
5. **Once every point is resolved**, write the agreed scope and acceptance criteria back onto the Jira ticket description and transition it to **Ready For Development**, without waiting to be asked.
6. **If grooming instead surfaces open questions that can't be resolved in this session** (e.g. the user needs to check with someone else), don't guess and don't leave the ticket ambiguously in the backlog: add a glanceable label to the ticket (e.g. `needs-info`, matching this project's existing kebab-case label convention) so it's visible on the board/backlog view, plus a comment enumerating the specific open questions. Leave the ticket's status unchanged — do not transition it to Ready For Development until the questions are actually answered.
7. **Only begin implementation once the ticket is confirmed Ready For Development** — whether because grooming just resolved it, or because it already was and no discussion was needed.

## Why runtime confirmation, not code reading

Code structure and runtime behavior diverge in exactly the places grooming cares about, and both directions have cost correction rounds here:

- **Called satisfied, actually broken.** The server-side action only needed `company_number`, so lookup-by-company-number-only looked fine in the code. In the browser it isn't: the Lookup button is a `formaction` submit inside the same `<form>` as Name, and `name` is `required: true`, so HTML5 validation blocks the whole submission no matter which submit button was clicked. The user had to send a screenshot to correct it.
- **Called missing, actually present.** Pushing to add hover text when the `title` attribute was already there and visible in the running UI.

The app is running and the user is usually on the exact page — check it.

## Verify

- Every point called "already satisfied" (or "already broken") was exercised in the running app, and the observed result was stated — not inferred from reading the code.
- Every open question raised was grounded in actual code/behavior read during step 1, not guessed.
- The user answered each judgment call before implementation started.
- The ticket reflects the outcome: either updated description + Ready For Development, or a `needs-info` label + comment with status left unchanged.
