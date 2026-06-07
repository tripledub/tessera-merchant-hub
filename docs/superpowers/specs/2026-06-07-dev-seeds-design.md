# Dev Seeds: Realistic Fake Data

**Date:** 2026-06-07
**Ticket:** MH-33 (pending)
**Branch:** to be created

---

## Goal

Replace the minimal demo seeds with realistic fake data so developers can work with a populated UI — merchants, shops, users, and payments — without needing a live tessera-core connection.

---

## Context

MerchantHub's seeds currently create 4 PSP demo users and print a note that core-owned data is seeded by tessera-core. In development the `payments` table exists as a local stub (via `CreateTesseraCoreStubTables` migration). `Tessera::Payment` is a `ReadOnlyRecord` and cannot be written to by normal ActiveRecord. We want rich fake payments in dev without changing production behaviour.

---

## Design Decisions

### Payments write path

Use a `Seeds::Payment` class defined inline at the top of `db/seeds.rb`. It subclasses `ApplicationRecord` directly, sets `self.table_name = "payments"`, and does **not** include the `readonly?` override. This class is never autoloaded — it exists only within the seed file. This keeps `Tessera::Payment` (and `ReadOnlyRecord`) untouched.

### Idempotency

- Merchants, shops, and users: `find_or_initialize_by` on their natural key — re-running seeds updates existing records without duplicating.
- Payments: truncated (`Seeds::Payment.delete_all`) then re-seeded on each run. They are fake development data; a fresh dataset on re-seed is desirable.

### Scope guard

The bulk of seeds.rb is wrapped in `if Rails.env.development?` so the PSP demo users (needed in all envs for Heroku/review apps) seed everywhere, but the Faker-generated data only runs locally.

### Faker gem

Added to the `development, test` group in `Gemfile` — available in both environments so factories can use it for realistic data without a separate Gemfile change later.

---

## Data Volume

| Entity | Count |
|---|---|
| Merchants | 5 |
| Shops per merchant | 2–3 (random) |
| Users per merchant | 2 (one `merchant_admin`, one `merchant_viewer`) |
| PSP users | 4 (unchanged) |
| Payments per shop | ~100, spread over last 90 days |

---

## Seed Data Shape

### Merchants
- `merchant_id`: `"merch_#{Faker::Alphanumeric.alphanumeric(number: 8)}"` — stable across re-runs via find_or_initialize_by
- `name`: `Faker::Company.name`
- `company_name`: `Faker::Company.name`
- `country`: random from `%w[GB DE FR NL IE]`

### Shops
- `shop_id`: `"shop_#{Faker::Alphanumeric.alphanumeric(number: 8)}"`
- `integration_account_id`: `"ia_#{Faker::Alphanumeric.alphanumeric(number: 12)}"` (stub)
- `name`: `"#{merchant.name} #{%w[Main EU US].sample}"`
- `country`: ISO-2 matching or near merchant country
- `test_mode`: first shop live, additional shops test mode
- `notification_url`: `nil` or `Faker::Internet.url(scheme: "https")`

### Users
- `merchant_admin`: `"admin@#{Faker::Internet.domain_name}"`
- `merchant_viewer`: `"viewer@#{Faker::Internet.domain_name}"`
- Password: same as demo password (`ENV.fetch("DEMO_USER_PASSWORD", "password123!")`)
- `merchant_id`: linked to their merchant

### Payments (~100 per shop)
- `status` distribution per shop:
  - `succeeded`: 60
  - `failed`: 15
  - `pending`: 10
  - `refunded`: 10
  - `voided`: 5
- `amount`: random between 1_000 and 500_000 (pence/cents)
- `currency`: weighted `%w[GBP GBP GBP EUR EUR USD]` (3:2:1)
- `merchant_reference`: present on 70% — `"ORD-#{Faker::Alphanumeric.alphanumeric(number: 8).upcase}"`
- `idempotency_key`: always present — `SecureRandom.uuid`
- `inserted_at` / `updated_at`: random within last 90 days, ordered oldest→newest within the batch
- `shop_id`: parent shop's `shop_id`

---

## Files Changed

| File | Action |
|---|---|
| `Gemfile` | Add `faker` to `development, test` group |
| `db/seeds.rb` | Rewrite — inline `Seeds::Payment` class, Faker data, scope guard |

No migrations. No model changes. No test changes.

---

## Testing Strategy

Seeds are not unit-tested. After running `bin/rails db:seed` in development, verify manually:
- `rails runner "puts Merchant.count"` → 5+ (plus any pre-existing)
- `rails runner "puts Shop.count"` → 10–15
- `rails runner "puts User.count"` → 14+ (10 merchant users + 4 PSP)
- `rails runner "puts Tessera::Payment.count"` → 1000–1500
- Sign in as `merchant-admin@tessera.test` → payments list shows data
