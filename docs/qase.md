# Testing with Qase

MerchantHub's document-journey scenarios live in [Qase](https://app.qase.io) — project code `MH`, epic [MH-304](https://shipcode.atlassian.net/browse/MH-304). Qase holds the manual test scenarios and their run history; some of those scenarios also have an automated RSpec system spec that can report its result straight into the same case.

## The manual suite

Everything in the "Document journey" suite is written as concrete steps + expected results, using synthetic data only — never real names, DOBs, or documents (see AGENTS.md → Data & Privacy).

To run a case: create/open an applicant, follow the case's steps, and record the result as a Qase test run. Two pieces of synthetic test data make this possible without real KYC documents or a real company:

- **Synthetic passports** — `spec/fixtures/files/specimen_passport_*.pdf`. Fictional issuing state ("Republic of Utopia"), watermarked "SPECIMEN", a silhouette instead of a photo, and a machine-readable zone with valid ICAO check digits. Verified against the real passport-extraction prompt, so they behave like a real scan.
- **The synthetic Utopia registry** ([MH-310](https://shipcode.atlassian.net/browse/MH-310)) — a fictional jurisdiction, code `xu`, behind the `SYNTHETIC_DATA_ENABLED` env flag (off by default, **never set in production**; see `.env.example` and `config/initializers/synthetic_data.rb`). With it on, the applicant form offers "Utopia (test data)" as a jurisdiction, and its company numbers return invented data from `config/synthetic/registry_scenarios.yml` — no real Companies House company needed. Current scenarios:

  | Number | Scenario |
  |---|---|
  | `XU000001` | Two active directors, one registered address |
  | `XU000002` | Officers named to match the synthetic specimen passports |

Set the flag locally with `SYNTHETIC_DATA_ENABLED=true bin/rails server` (or export it for the session). More scenarios (error paths, PSC chains, nominees) are tracked as follow-on stories under [MH-230](https://shipcode.atlassian.net/browse/MH-230).

## The automated layer

Some manual cases have an RSpec system spec exercising the same journey in a real, local, headless Chrome browser ([MH-314](https://shipcode.atlassian.net/browse/MH-314)). These are fast, deterministic regression checks — they don't replace the manual suite, which stays the place a reviewer signs off and where new scenarios get designed first.

- **Driver:** Capybara + [Cuprite](https://github.com/rubycc/cuprite) (Ferrum), driving a local Chrome install directly — no chromedriver to keep in sync. System specs are **local only**; there's no browser in the CI image yet.
- **Extraction is stubbed**, not live: `Kyc::DocumentExtractorService.call` returns ground truth already verified against the real Claude endpoint for that fixture. The specs exercise our app logic (matching, principal creation, the UI) — not Claude's OCR.
- **Linking to Qase:** tag the example with the case's ID, `qase_id: <n>`, matching an existing case in the `MH` project. The tag never triggers anything by itself.
- **Jobs run inline:** the app enqueues via ActiveJob; nothing runs it until you call `perform_enqueued_jobs`. No ActionCable/AnyCable runs in the test environment either, so a server-side broadcast never reaches the page — after running jobs, `visit` (reload) rather than wait on a live update.
- **Signing in:** `sign_in_via_form(user, password:)` (`spec/support/system_sign_in.rb`) — Devise's `sign_in` test helper sets a Warden session a real browser never sees, so system specs sign in through the actual form.
- **The confirm dialog on "Run extraction"** is an app-level custom modal (`Turbo.config.forms.confirm` in `application.js`), not a native `window.confirm` — use `run_extraction!` (`spec/support/system_document_pipeline.rb`), not Capybara's `accept_confirm`.
- **Watch for false-positive content checks:** the dropzone's client-side file-preview list also contains the uploaded filename, so an unscoped `have_content(filename)` can pass even if the actual upload never reached the server. Assert on server-rendered content instead (e.g. `have_css("[data-controller='classification']")`).

Run just the automated, Qase-linked specs:

```bash
bundle exec rspec --tag qase_id
```

### Reporting results to Qase

There's no official Qase Ruby/RSpec reporter, and RSpec's own `--format json` drops custom example metadata (so a bare `qase_id:` tag never reaches a report built from it). `lib/qase_id_formatter.rb` is a small custom formatter that captures just the tagged examples and their outcome.

```bash
bin/rails "qase:report[optional run title]"
```

This runs the `qase_id`-tagged specs, then creates a **new** test run in the Qase `MH` project and posts each result into it — every invocation is a new run, not an update to a previous one. Plain `bundle exec rspec` never needs a Qase credential and never makes a network call; reporting is a separate, explicit step.

**Credential:** `Qase::ResultsReporter` reads `qase.api_key` from Rails credentials first (`rails credentials:edit`; committed, shared with the team — generate one in Qase under your profile's API tokens), falling back to the `QASE_API_TOKEN` env var for a local-only token. Never paste a token into chat, a commit, or a PR description.

**⚠️ On `lib/*.rb` files (MH-316):** `lib/qase_id_formatter.rb` briefly crashed every UAT/production boot. It sits directly under `lib/`, which `config.autoload_lib` (`config/application.rb`) both autoloads *and eager-loads* except for `lib/assets`/`lib/tasks` — and the formatter's own `require "rspec/core"` only resolves where rspec-rails is installed, i.e. dev and test, **never** the production bundle. Every check in this repo's normal dev loop (`zeitwerk:check`, the full suite, the pre-commit gate) runs where that gem *is* present, so this was invisible until it hit a real production-shaped bundle. It's now excluded via `config.autoload_lib(ignore: [...])`, same as `lib/tasks`. If you add another standalone script-like file under `lib/` (not a proper `Module::Class` meant to be autoloaded), either add it to that ignore list or move it somewhere Zeitwerk won't eager-load — there is no automated check that catches this class of bug today.

### Adding a new automated case

1. Write the manual case in Qase first (or confirm one already exists) — the `qase_id` must match a real case, or the run-creation API call fails.
2. Write the system spec, tag it `qase_id: <that case's id>`, type: `:system`.
3. Run it on its own (`bundle exec rspec path/to/spec.rb`) until it's green against the real app — not mocked at the controller/request level.
4. `bin/rails qase:report` to confirm it reports correctly, and check the resulting run in Qase.
