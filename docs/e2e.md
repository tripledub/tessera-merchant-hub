# Local E2E Setup With tessera-core

This guide documents the local MerchantHub plus tessera-core setup. It reflects
ADR-007: tessera-core owns merchants, shops, credentials, payments, audit events,
and webhook data. MerchantHub owns portal users and reads/provisions core data.

## Current Seed Boundary

MerchantHub `db/seeds.rb` creates only demo portal users:

| Role | Email | Merchant ID |
| --- | --- | --- |
| `psp_admin` | `psp-admin@tessera.test` | none |
| `psp_support` | `psp-support@tessera.test` | none |
| `merchant_admin` | `merchant-admin@tessera.test` | `DEMO_MERCHANT_ID` |
| `merchant_viewer` | `merchant-viewer@tessera.test` | `DEMO_MERCHANT_ID` |

Default password: `DEMO_USER_PASSWORD`, which defaults to `password123!`.

MerchantHub deliberately does not seed core-owned tables. In specs, stub versions
of those tables are created by `spec/support/tessera_tables.rb`; in local e2e,
they should come from tessera-core.

## Environment

Copy `.env.example` to `.env` and keep these values aligned with tessera-core:

```sh
TESSERA_CORE_URL=http://localhost:4000
TESSERA_INTERNAL_API_KEY=dev-internal-api-key
DEMO_MERCHANT_ID=merch_demo
DEMO_USER_PASSWORD=password123!
```

`TESSERA_INTERNAL_API_KEY` is the service-to-service key MerchantHub sends to
tessera-core for provisioning, refund, void, and credential operations. Both apps
must use the same value.

## Setup Order

1. Start the shared Postgres instance used by both apps.
2. In `tessera-core`, migrate and seed:

   ```sh
   mix setup
   ```

   Current core seeds create the development shop credential `shop_test` /
   `sk_test`.

3. In `tessera-merchant-hub`, prepare and seed:

   ```sh
   cp .env.example .env
   bin/setup --skip-server
   ```

4. Boot both apps:

   ```sh
   # tessera-core
   mix phx.server

   # tessera-merchant-hub
   bin/dev
   ```

5. Sign in to MerchantHub with one of the demo users from the table above.

## Current E2E Limitations

tessera-core currently seeds `shop_test` / `sk_test`, but that seed does not yet
include the richer merchant/shop metadata MerchantHub expects for fully
representative merchant-scoped browsing. Until core adds merchant IDs and shop
metadata to its local seeds, PSP demo users are the best fit for inspecting
core-owned records in MerchantHub.

Core-backed actions such as refunds, voids, shop provisioning, and credential
management also require the corresponding tessera-core internal endpoints to be
available locally. MerchantHub request specs use WebMock where those endpoints
are still ahead of core implementation.

## Test-Only Stub Tables

MerchantHub specs create test-only stand-ins for core tables in
`spec/support/tessera_tables.rb`. Do not mirror that in development. In local e2e
the source of truth should be tessera-core migrations and seeds.
