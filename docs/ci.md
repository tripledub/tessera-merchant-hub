# CI pipeline

MerchantHub uses GitHub Actions. All jobs must pass before a PR can merge to `main`.

## Jobs

| Job | Tool | Runs on |
|---|---|---|
| `scan_ruby` | Brakeman, bundler-audit | PR + push to main |
| `scan_js` | importmap audit | PR + push to main |
| `lint` | RuboCop (+ performance, rspec extensions) | PR + push to main |
| `test` | RSpec + SimpleCov (90% minimum) | PR + push to main |

Coverage reports are uploaded as GitHub Actions artifacts (7-day retention).

## PCI-DSS SDLC alignment

Cross-reference: [GW-30](https://shipcode.atlassian.net/browse/GW-30) Security & compliance.

| PCI-DSS requirement | Control | tessera-core equivalent |
|---|---|---|
| 6.3.2 — Inventory of bespoke software | All app code in version-controlled repo; linear history enforced on `main` | Same |
| 6.4.1 — Detect security vulnerabilities (SAST) | Brakeman on every PR and push to main | `mix sobelow --exit medium` |
| 6.4.2 — Address common vulnerabilities | Brakeman covers OWASP Top 10 for Rails (SQLi, XSS, mass assignment, etc.) | Sobelow |
| 6.3.3 — All software components protected from known vulnerabilities | `bundler-audit check --update` — fetches fresh advisory DB; fails on known CVEs | `mix deps.audit` |
| 6.3.3 — Retired/unsupported components | bundler-audit flags yanked gems; Dependabot configured for automated PRs | `mix hex.audit` |
| 6.2.4 — Prevent common coding vulnerabilities | RuboCop with Rails, performance, and RSpec extensions; fails build on offences | `mix credo --strict` |
| 6.4.3 — Automated security testing in pipeline | All of the above run automatically; no manual bypass path to `main` | Same |

## Branch protection

`main` is protected:
- Direct pushes blocked
- All four CI jobs must pass before merge
- Stale reviews dismissed on new commits
- Linear history (squash/rebase only — no merge commits)

## Adding a security exception

If a CVE advisory must be ignored (e.g. false positive, no fix available), document it in `.bundler-audit.yml` with:
- Advisory ID
- Reason for exception
- Review date (max 90 days)

This mirrors tessera-core's `.audit-ignore` convention.
