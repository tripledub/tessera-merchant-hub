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

## tessera-core E2E

MerchantHub does not seed shops, payments, credentials, audit events, or webhook
data. Those tables are owned by tessera-core. See [docs/e2e.md](docs/e2e.md) for
the local two-app setup and current limitations.

## Tests

```sh
COVERAGE=false bundle exec rspec
```
