# Tessera MerchantHub

MerchantHub is the Rails management console for Tessera. It owns portal users
and reads/provisions tessera-core control-plane data through read-only models and
internal API calls.

## Local Setup

```sh
cp .env.example .env
bin/setup --skip-server
bin/dev
```

`bin/setup` installs gems, prepares the database, and loads idempotent demo seed
users from `db/seeds.rb`.

## Demo Users

All demo users use `DEMO_USER_PASSWORD`, which defaults to `password123!`.

| Role | Email |
| --- | --- |
| PSP admin | `psp-admin@tessera.test` |
| PSP support | `psp-support@tessera.test` |
| Merchant admin | `merchant-admin@tessera.test` |
| Merchant viewer | `merchant-viewer@tessera.test` |

Merchant demo users are linked to `DEMO_MERCHANT_ID`, which defaults to
`merch_demo`.

## Email Previews

In development, outgoing mail is captured locally by
[`letter_opener_web`](https://github.com/fgrehm/letter_opener_web) instead of
being sent — visit `http://localhost:3000/letter_opener` after triggering a
delivery to inspect the rendered HTML and plain-text message, with any links
(invitation, confirmation, password reset) pointing at your local server and
clickable from the preview. The route is mounted only when
`Rails.env.development?`, so it's unavailable in UAT/production, and test-env
mail assertions are unaffected (`config.action_mailer.delivery_method = :test`
there).

To exercise a journey end to end locally:

- **Applicant invitation** — create and invite an applicant from the staff UI,
  then open the preview to get the registration link.
- **Devise confirmation / password reset** — trigger `ApplicantUser`
  confirmation or "forgot password" from the portal sign-in screen; both are
  enabled (`:confirmable`, `:recoverable`) and captured the same way.

## tessera-core E2E

MerchantHub does not seed shops, payments, credentials, audit events, or webhook
data. Those tables are owned by tessera-core. See [docs/e2e.md](docs/e2e.md) for
the local two-app setup and current limitations.

## Tests

```sh
COVERAGE=false bundle exec rspec
```
