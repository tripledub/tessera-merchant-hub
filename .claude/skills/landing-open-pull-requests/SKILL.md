---
name: landing-open-pull-requests
description: Surveys the repo's open pull requests before new work starts and lands the stale ones — brings a drifted branch up to date with main, resolves the conflicts, re-runs the suite, and gets it merged. Use when the user says "lets check the current PRs first", asks which PRs are open or in what order they should merge, or points at a PR that "has been sitting for a week or more" and "needs a rebase and a recheck" — and before picking up a new ticket or branch while PRs are still open.
---

# Landing Open Pull Requests

Open PRs are unfinished work, not a backlog. Survey them before starting anything new, and clear the stale ones rather than leaving them to drift further.

## Steps

1. **Survey first.** `git fetch`, then list the open PRs (GitHub MCP `list_pull_requests`, or `gh pr list`). For each, report its age, its target branch, and its drift: `git rev-list --left-right --count origin/main...origin/<branch>` (behind/ahead). Call out which PRs touch the same files, and the order they should merge in so the later ones don't inherit avoidable conflicts.
2. **Decide how to bring a drifted branch up to date — ask, don't assume.** Large drift is not a quick rebase. Rebasing rewrites the branch and needs a force-push, which this repo's rules require the user to OK explicitly (`AGENTS.md` → Git Workflow). Merging `origin/main` into the branch gets the same practical result — branch current, conflicts resolved once, PR unblocked — with no rewrite. Put both options to the user with `AskUserQuestion`, stating the drift counts, and recommend the merge.
3. **Work where the branch already lives.** If a worktree exists for it (`.worktrees/<branch>`), use that instead of checking the branch out in the main clone. Confirm `git status` is clean there before touching anything.
4. **Update the branch:** `git merge origin/main --no-edit`.
5. **Resolve conflicts one file at a time**, reading the surrounding code before editing — keep both sides' intent rather than picking a side:
   - `config/locales/en.yml` — merge both key sets, preserving alphabetical key order (`i18n-tasks health` runs in the pre-commit hook).
   - `db/schema.rb` — the `define(version: ...)` line takes the latest migration timestamp *after* the merge; confirm it with `ls db/migrate | sort | tail -20` rather than trusting either side.
   - Spec files — two independent examples are siblings; keep both.
6. **Prove no markers survive:** `grep -rln "<<<<<<<\|=======\|>>>>>>>" --include="*.rb" --include="*.yml" --include="*.erb" . | grep -v node_modules`. Check each hit — comment dividers (e.g. in `db/seeds.rb`) are false positives, an unresolved conflict is not.
7. **Stage and confirm the merge is complete:** `git add <resolved files>` then `git status --short | grep "^UU\|^AA\|^DD"` must return nothing.
8. **Re-check before committing:** run the full suite `bundle exec rspec`. Let the `lefthook` pre-commit hooks run — never `--no-verify`.
9. **Push and land it.** Push the branch, wait for the PR's GitHub checks to go green, and merge. Report the merge; don't leave the PR sitting once it is current and green.
10. **Stop at the merge for Jira.** Moving the ticket to **UAT** or **Done** is the user's deployment and QA sign-off (`AGENTS.md` → Jira Workflow).

## Verify

- The survey named every open PR with its drift and the recommended merge order — not just the one PR the user mentioned.
- No branch history was rewritten and nothing was force-pushed without the user explicitly choosing it.
- No conflict markers remain, and `git status` shows no unmerged paths.
- `bundle exec rspec` passed on the updated branch and the PR's checks are green before merging.
