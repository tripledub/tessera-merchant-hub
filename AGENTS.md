# AGENTS.md

This file is the canonical, tool-agnostic source of instructions for any AI
agent working in this repository (Claude Code, Codex, Copilot, etc.). Where a
tool needs its own config format, symlink that file to this one rather than
maintaining a separate copy. Rules here override an agent's default
behavior; a user's direct instructions in a session always take precedence
over this file.

## Git Workflow

- Never commit, merge, or push directly to `main` (or `uat`) — always work on
  a feature branch and open a Pull Request. This applies even for small or
  "obviously safe" changes.
- Branch off `origin/main`, not local `main` — local `main` can silently
  diverge from `origin/main` (stale commits, unpushed work). Before starting
  new work: `git fetch && git checkout -b <branch> origin/main`.
- Branch naming: `<type>/<MH-issue-number>-<short-description>`, e.g.
  `feature/mh-160-transcript-text-export`,
  `fix/mh-176-address-card-turbo-stream`, `chore/mh-15-pagy-v43-upgrade`,
  `hotfix/ai-classifier-fenced-json`. Use `feature/`, `fix/`, `chore/`,
  `hotfix/`, or `docs/` depending on the nature of the change.
- Prefer small, focused commits with messages that explain *why*, not just
  *what*.
- Never force-push, skip hooks (`--no-verify`), or bypass signing unless
  explicitly asked.
- Before any destructive git command (`reset --hard`, `checkout --`,
  `clean -f`), run `git status` and stash or preserve anything uncommitted.

## Jira Workflow

This board's statuses: **To Do** (needs more detail before it's workable) →
**Ready for Development** (workable, can be picked up) → **In Progress** →
**In Review** (PR open) → **UAT** (merged, deployed) → **Done** (passed QA,
production-ready).

- Before starting work on a ticket, confirm its status is **Ready for
  Development**. If it's still **To Do**, stop and ask — don't assume the
  ticket has enough detail to implement.
- When starting implementation, transition the ticket to **In Progress**.
- When opening a PR, transition the ticket to **In Review**.
- Do not transition a ticket to **UAT** or **Done** — those are deployment
  and QA sign-off steps owned by the user.

## Testing & TDD

- Write tests first (TDD): a failing test, then the minimal code to pass it,
  then refactor.
- Full suite must pass before opening a PR: `bundle exec rspec`.
- Pre-commit hooks (`lefthook`) run automatically and must pass: `rubocop`
  (autocorrects), `brakeman`, `bundler-audit`, `importmap-audit`,
  `zeitwerk:check`, `i18n-tasks health`, `rspec`. Don't bypass with
  `--no-verify`.
- New i18n strings go through `config/locales/en.yml`; `i18n-tasks health`
  will fail on missing or unused keys.
- If the suite feels slower than it should, re-profile with `test-prof`
  (already bundled): `RD_PROF=1 bundle exec rspec` reports the slowest
  suites by setup time (RSpecDissect); `FPROF=1 bundle exec rspec` reports
  factory usage counts/time, including cascade creation via associations
  (FactoryProf). Compare against the MH-280 baseline (1862 examples, ~40s,
  `kyc_document`'s ActiveStorage `.attach` in its factory as the single
  largest cost) before assuming a new slowdown is code, not data volume.

## Architecture Orientation (lightweight)

- Rails 8 app. Business logic belongs in **presenters** (`app/presenters/`),
  not views or controllers — view templates should be thin. Presenters
  inherit from `BasePresenter` and expose data via `presents :model`; use
  `present(model) { |p| ... }` in views. Presenters delegate unknown methods
  to the view via `method_missing` (`@template`), so you can call view
  helpers (`link_to`, `t`, etc.) directly inside a presenter as if it were
  the view — this is what lets business logic move out of `.erb` files
  without losing access to Rails helpers.
- Authorization is via **Pundit** (`app/policies/`) — every controller action
  should call `authorize`/`policy_scope`. `rescue_from
  Pundit::NotAuthorizedError` is handled centrally in
  `ApplicationController#user_not_authorized`; if you add a new response
  format, add its branch there too or unauthorized requests in that format
  will 406 instead of 403.
- Controllers use `decent_exposure` (`expose`) where present — check for an
  existing `expose` before adding manual instance variables.
- Frontend: Stimulus controllers (vanilla JS via importmap, auto-registered
  from `app/javascript/controllers/`) + Turbo (`turbo_stream`,
  `Turbo.config.forms.confirm`). Filename `snake_case_controller.js` →
  `data-controller="kebab-case"`.
- `Rails.env.production?` cannot distinguish UAT from production — both run
  `RAILS_ENV=production` in this app's infra. Don't gate behavior on it; use
  an explicit env var instead.
- MerchantHub reads/provisions `tessera-core` control-plane data via
  read-only models and internal API calls — it does not own shops, payments,
  credentials, audit events, or webhook data itself (see `docs/e2e.md`).

## Data & Privacy

- Never use real people's names (or other real PII — emails, phone numbers,
  addresses) in test fixtures, seed data, ticket descriptions, commit
  messages, code comments, or anywhere else in the repo or its tooling
  output. This includes names captured incidentally in a screenshot used to
  illustrate a bug — describe or redact the record instead of quoting the
  name (e.g. "the applicant's document" rather than a real applicant's
  name). Use clearly synthetic placeholders (`Test Applicant`,
  `applicant@example.com`, existing factory/seed defaults) instead.

## Tooling / Working Files

- This repo uses the Superpowers skill framework (Claude Code and compatible
  agents). Working files it produces — specs in `docs/superpowers/specs/`,
  plans in `docs/superpowers/plans/` — are local-reference-only scratch
  documents, **not** shared documentation. Never commit, push, or open a PR
  containing them. Shared knowledge (decisions, designs) belongs in Jira, not
  these files.
- When following a Superpowers workflow (brainstorming → spec → plan →
  execution), respect its gates — e.g. don't skip straight to implementation
  without an approved design for non-trivial work.
