# MH-29: Merchant & Shop Profile Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow merchant admins to edit their merchant profile and shop display name; give PSP admins a searchable merchant directory with a per-merchant detail page.

**Architecture:** Thin controllers using `decent_exposure` (new actions only) delegating mutations to service objects (`Merchants::UpdateProfile`, `Shops::UpdateSettings`). AR models own validations. Pundit policies own access rules. Stories implemented in order: MH-40 → MH-42 → MH-41.

**Tech Stack:** Rails 8, Hotwire (Turbo Frames for search), Pundit, Pagy, `decent_exposure` gem, RSpec request specs.

---

## Codebase orientation

- **`app/models/merchant.rb`** — MH-owned `Merchant` AR model. `merchant_id` is the business key (string). Has `name`, `company_name`, `country`. Writable (not ReadOnlyRecord).
- **`app/models/shop.rb`** — MH-owned `Shop` AR model. `shop_id` is the business key. Has `notification_url`, `test_mode`. `Tessera::Shop = ::Shop` (alias). `to_param` returns `shop_id`.
- **`app/controllers/merchants_controller.rb`** — Currently only `new`/`create`. PSP onboarding flow; uses `ControlPlane::MerchantProvisioner`.
- **`app/controllers/shops_controller.rb`** — Has `edit`/`update` using `ControlPlane::ShopConfigStore.update!` for local shop config.
- **`app/policies/merchant_policy.rb`** — Headless today (`new?`/`create?` only, no Scope).
- **`app/policies/shop_policy.rb`** — Has full CRUD policy + `Scope`.
- **`config/routes.rb`** — `resources :merchants, only: %i[new create]`. Needs `index show edit update` added.
- **`spec/factories/merchants.rb`** — `create(:merchant)` gives `merchant_id`, `name`, `company_name`, `country`.
- **`spec/factories/shops.rb`** — `create(:shop)` / `create(:tessera_shop)` (both exist). Has `:with_merchant` trait.
- **`spec/factories/users.rb`** — traits: `:psp_admin`, `:psp_support`, `:merchant_admin`, `:merchant_viewer`.
- **`spec/requests/shops_spec.rb`** — Has `PATCH /shops/:id` context with `ShopConfigStore` stub. Task 7 must update that stub.
- **Test helpers:** `sign_in user` (Devise). `let_it_be` from `test-prof`. RSpec request specs in `spec/requests/`.
- **View patterns:** `form-label`, `form-input`, `btn-primary`, `btn-secondary` CSS classes. i18n via `t('.key')`. Card wrapper `<div class="card">`. All strings in `config/locales/en.yml`.

---

## File map

| Task | Action | File |
|---|---|---|
| 1 | Modify | `Gemfile` |
| 2 | Create | `db/migrate/TIMESTAMP_add_profile_fields_to_merchants.rb` |
| 3 | Create | `db/migrate/TIMESTAMP_add_display_name_to_shops.rb` |
| 4 | Modify | `app/models/merchant.rb` |
| 4 | Create | `app/services/merchants/update_profile.rb` |
| 4 | Modify | `spec/models/merchant_spec.rb` |
| 4 | Create | `spec/services/merchants/update_profile_spec.rb` |
| 5 | Modify | `app/policies/merchant_policy.rb` |
| 6 | Modify | `app/controllers/merchants_controller.rb` |
| 6 | Create | `app/views/merchants/edit.html.erb` |
| 6 | Modify | `config/routes.rb` |
| 6 | Modify | `config/locales/en.yml` |
| 6 | Create/Modify | `spec/requests/merchants_spec.rb` |
| 7 | Modify | `app/models/shop.rb` |
| 7 | Create | `app/services/shops/update_settings.rb` |
| 7 | Modify | `app/controllers/shops_controller.rb` |
| 7 | Modify | `app/views/shops/edit.html.erb` |
| 7 | Modify | `config/locales/en.yml` |
| 7 | Create | `spec/services/shops/update_settings_spec.rb` |
| 7 | Modify | `spec/requests/shops_spec.rb` |
| 8 | Modify | `app/controllers/merchants_controller.rb` |
| 8 | Create | `app/views/merchants/index.html.erb` |
| 8 | Create | `app/views/merchants/show.html.erb` |
| 8 | Modify | `config/locales/en.yml` |
| 8 | Modify | `spec/requests/merchants_spec.rb` |

---

## Task 1: Add decent_exposure gem

**Files:**
- Modify: `Gemfile`

- [ ] **Step 1: Add gem to Gemfile**

Open `Gemfile` and add after the `gem "pundit"` line:

```ruby
gem "decent_exposure"
```

- [ ] **Step 2: Install**

```bash
cd /path/to/tessera-merchant-hub
bundle install
```

Expected: `Bundle complete!` with `decent_exposure` in the lock file.

- [ ] **Step 3: Verify it loads**

```bash
bin/rails runner "puts DecentExposure.name"
```

Expected: `DecentExposure`

- [ ] **Step 4: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "MH-29: add decent_exposure gem"
```

---

## Task 2: Merchant profile columns migration

**Files:**
- Create: `db/migrate/TIMESTAMP_add_profile_fields_to_merchants.rb`

- [ ] **Step 1: Generate migration**

```bash
bin/rails generate migration AddProfileFieldsToMerchants \
  contact_email:string support_url:string \
  address_line1:string city:string country_code:string
```

Expected: creates `db/migrate/TIMESTAMP_add_profile_fields_to_merchants.rb`.

- [ ] **Step 2: Verify migration content**

The generated file should look like:

```ruby
class AddProfileFieldsToMerchants < ActiveRecord::Migration[8.1]
  def change
    add_column :merchants, :contact_email, :string
    add_column :merchants, :support_url, :string
    add_column :merchants, :address_line1, :string
    add_column :merchants, :city, :string
    add_column :merchants, :country_code, :string
  end
end
```

All columns nullable (no `null: false`) — correct, all fields are optional.

- [ ] **Step 3: Run migration**

```bash
bin/rails db:migrate
```

Expected: `== AddProfileFieldsToMerchants: migrated`

- [ ] **Step 4: Confirm schema**

```bash
grep -A 20 'create_table "merchants"' db/schema.rb
```

Expected: all five new columns present.

- [ ] **Step 5: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "MH-40: add merchant profile columns (contact_email, support_url, address, city, country_code)"
```

---

## Task 3: Display name column migration

**Files:**
- Create: `db/migrate/TIMESTAMP_add_display_name_to_shops.rb`

- [ ] **Step 1: Generate migration**

```bash
bin/rails generate migration AddDisplayNameToShops display_name:string
```

- [ ] **Step 2: Verify and run**

```bash
bin/rails db:migrate
```

Expected: `== AddDisplayNameToShops: migrated`

- [ ] **Step 3: Confirm schema**

```bash
grep "display_name" db/schema.rb
```

Expected: `t.string "display_name"` in the shops table block.

- [ ] **Step 4: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "MH-42: add display_name column to shops"
```

---

## Task 4: Merchant model validations + UpdateProfile service

**Files:**
- Modify: `app/models/merchant.rb`
- Create: `app/services/merchants/update_profile.rb`
- Modify: `spec/models/merchant_spec.rb`
- Create: `spec/services/merchants/update_profile_spec.rb`

- [ ] **Step 1: Write failing model spec examples**

Open `spec/models/merchant_spec.rb` and add after the existing `describe "persistence"` block:

```ruby
describe "validations — contact_email" do
  it "is valid when blank" do
    merchant = build(:merchant, contact_email: "")
    expect(merchant).to be_valid
  end

  it "is valid with a well-formed email" do
    merchant = build(:merchant, contact_email: "billing@acme.com")
    expect(merchant).to be_valid
  end

  it "is invalid with a malformed email" do
    merchant = build(:merchant, contact_email: "not-an-email")
    expect(merchant).not_to be_valid
    expect(merchant.errors[:contact_email]).to be_present
  end
end

describe "validations — country_code" do
  it "is valid when blank" do
    merchant = build(:merchant, country_code: nil)
    expect(merchant).to be_valid
  end

  it "upcases the value before validation" do
    merchant = build(:merchant, country_code: "gb")
    merchant.valid?
    expect(merchant.country_code).to eq("GB")
  end

  it "is valid with a 2-letter uppercase code" do
    merchant = build(:merchant, country_code: "GB")
    expect(merchant).to be_valid
  end

  it "is invalid with a 3-letter code" do
    merchant = build(:merchant, country_code: "GBR")
    expect(merchant).not_to be_valid
    expect(merchant.errors[:country_code]).to be_present
  end
end
```

- [ ] **Step 2: Run failing specs**

```bash
bin/rspec spec/models/merchant_spec.rb --format documentation
```

Expected: new examples FAIL (no validations yet).

- [ ] **Step 3: Implement model validations**

Replace the full content of `app/models/merchant.rb`:

```ruby
# frozen_string_literal: true

# MerchantHub-owned merchant (company) record. ADR-007.
class Merchant < ApplicationRecord
  has_many :shops,
    foreign_key: :merchant_id,
    primary_key: :merchant_id,
    inverse_of: :merchant,
    dependent: :restrict_with_error

  validates :merchant_id, presence: true, uniqueness: true
  validates :name, presence: true
  validates :contact_email,
    format: { with: URI::MailTo::EMAIL_REGEXP },
    allow_blank: true
  validates :country_code,
    format: { with: /\A[A-Z]{2}\z/ },
    allow_blank: true

  before_validation :upcase_country_code

  private

  def upcase_country_code
    self.country_code = country_code&.upcase
  end
end
```

- [ ] **Step 4: Run model specs**

```bash
bin/rspec spec/models/merchant_spec.rb --format documentation
```

Expected: all examples PASS.

- [ ] **Step 5: Write failing service spec**

Create `spec/services/merchants/update_profile_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Merchants::UpdateProfile do
  let(:merchant) { create(:merchant, contact_email: nil, country_code: nil) }

  describe ".call" do
    it "updates permitted profile fields" do
      result = described_class.call(merchant, {
        contact_email: "billing@acme.com",
        support_url: "https://acme.com/support",
        address_line1: "1 High Street",
        city: "London",
        country_code: "gb"
      })

      expect(result.errors).to be_empty
      expect(merchant.reload.contact_email).to eq("billing@acme.com")
      expect(merchant.reload.city).to eq("London")
      expect(merchant.reload.country_code).to eq("GB")
    end

    it "returns the merchant with errors when invalid" do
      result = described_class.call(merchant, { contact_email: "not-an-email" })
      expect(result.errors[:contact_email]).to be_present
    end

    it "does not update unpermitted fields (e.g. merchant_id)" do
      original_id = merchant.merchant_id
      described_class.call(merchant, { merchant_id: "hacked_id" })
      expect(merchant.reload.merchant_id).to eq(original_id)
    end
  end
end
```

- [ ] **Step 6: Run failing service spec**

```bash
bin/rspec spec/services/merchants/update_profile_spec.rb --format documentation
```

Expected: FAIL — `uninitialized constant Merchants::UpdateProfile`.

- [ ] **Step 7: Implement the service**

Create `app/services/merchants/update_profile.rb`:

```ruby
# frozen_string_literal: true

module Merchants
  class UpdateProfile
    PERMITTED = %i[contact_email support_url address_line1 city country_code].freeze
    private_constant :PERMITTED

    def self.call(merchant, params) = new(merchant, params).call

    def initialize(merchant, params)
      @merchant = merchant
      @params   = params.to_h.symbolize_keys.slice(*PERMITTED)
    end

    def call
      @merchant.update(@params)
      @merchant
    end
  end
end
```

- [ ] **Step 8: Run service specs**

```bash
bin/rspec spec/services/merchants/update_profile_spec.rb --format documentation
```

Expected: all PASS.

- [ ] **Step 9: Run full suite to check for regressions**

```bash
bin/rspec --format progress
```

Expected: 0 failures.

- [ ] **Step 10: Commit**

```bash
git add app/models/merchant.rb \
        app/services/merchants/update_profile.rb \
        spec/models/merchant_spec.rb \
        spec/services/merchants/update_profile_spec.rb
git commit -m "MH-40: Merchant model validations + UpdateProfile service"
```

---

## Task 5: MerchantPolicy

**Files:**
- Modify: `app/policies/merchant_policy.rb`

The policy currently has only `new?` and `create?`. We need to add `index?`, `show?`, `edit?`, `update?`, and a `Scope` inner class.

- [ ] **Step 1: Write failing policy spec**

Check if `spec/policies/merchant_policy_spec.rb` exists:

```bash
ls spec/policies/
```

If it doesn't exist, create `spec/policies/merchant_policy_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe MerchantPolicy, type: :policy do
  let(:psp_admin)      { build(:user, :psp_admin) }
  let(:psp_support)    { build(:user, :psp_support) }
  let(:merchant_admin) { build(:user, :merchant_admin, merchant_id: "merch_abc") }
  let(:merchant_viewer){ build(:user, :merchant_viewer, merchant_id: "merch_abc") }
  let(:own_merchant)   { build(:merchant, merchant_id: "merch_abc") }
  let(:other_merchant) { build(:merchant, merchant_id: "merch_xyz") }

  describe "index?" do
    it "permits psp_admin"   { expect(described_class.new(psp_admin, Merchant).index?).to be true }
    it "permits psp_support" { expect(described_class.new(psp_support, Merchant).index?).to be true }
    it "denies merchant_admin" { expect(described_class.new(merchant_admin, Merchant).index?).to be false }
  end

  describe "show?" do
    it "permits psp_admin on any merchant"    { expect(described_class.new(psp_admin, other_merchant).show?).to be true }
    it "permits merchant_admin on own"        { expect(described_class.new(merchant_admin, own_merchant).show?).to be true }
    it "denies merchant_admin on other"       { expect(described_class.new(merchant_admin, other_merchant).show?).to be false }
    it "denies merchant_viewer on own"        { expect(described_class.new(merchant_viewer, own_merchant).show?).to be false }
  end

  describe "edit? / update?" do
    it "permits psp_admin on any merchant"    { expect(described_class.new(psp_admin, other_merchant).edit?).to be true }
    it "permits merchant_admin on own"        { expect(described_class.new(merchant_admin, own_merchant).edit?).to be true }
    it "denies merchant_admin on other"       { expect(described_class.new(merchant_admin, other_merchant).edit?).to be false }
    it "denies merchant_viewer"               { expect(described_class.new(merchant_viewer, own_merchant).edit?).to be false }
    it "update? matches edit?"                { expect(described_class.new(merchant_admin, own_merchant).update?).to be true }
  end

  describe "Scope" do
    before do
      create(:merchant, merchant_id: "merch_abc")
      create(:merchant, merchant_id: "merch_xyz")
    end

    it "psp_admin sees all" do
      scope = MerchantPolicy::Scope.new(psp_admin, Merchant).resolve
      expect(scope.count).to eq(2)
    end

    it "merchant_admin sees only own merchant" do
      scope = MerchantPolicy::Scope.new(merchant_admin, Merchant).resolve
      expect(scope.map(&:merchant_id)).to contain_exactly("merch_abc")
    end

    it "merchant_viewer sees nothing" do
      scope = MerchantPolicy::Scope.new(merchant_viewer, Merchant).resolve
      expect(scope).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run failing policy spec**

```bash
bin/rspec spec/policies/merchant_policy_spec.rb --format documentation
```

Expected: FAIL — missing methods.

- [ ] **Step 3: Implement the policy**

Replace the full content of `app/policies/merchant_policy.rb`:

```ruby
# frozen_string_literal: true

class MerchantPolicy < ApplicationPolicy
  def new?    = psp_admin?
  def create? = psp_admin?
  def index?  = psp_role?
  def show?   = psp_role? || own_merchant?
  def edit?   = psp_admin? || (merchant_admin? && own_merchant?)
  def update? = edit?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all                                      if user.psp_role?
      return scope.where(merchant_id: user.merchant_id)    if user.merchant_admin?

      scope.none
    end
  end

  private

  def own_merchant?
    user.merchant_id.present? && user.merchant_id == record.merchant_id
  end
end
```

Check what helpers `psp_role?`, `merchant_admin?` etc. look like in `app/policies/application_policy.rb` to confirm they exist:

```bash
cat app/policies/application_policy.rb
```

If the helpers don't exist, add them there. They almost certainly do — they're used throughout.

- [ ] **Step 4: Run policy specs**

```bash
bin/rspec spec/policies/merchant_policy_spec.rb --format documentation
```

Expected: all PASS.

- [ ] **Step 5: Full suite**

```bash
bin/rspec --format progress
```

Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/policies/merchant_policy.rb spec/policies/merchant_policy_spec.rb
git commit -m "MH-40: expand MerchantPolicy with index/show/edit/update and Scope"
```

---

## Task 6: MerchantsController edit/update + view + routes + i18n + request specs (MH-40)

**Files:**
- Modify: `app/controllers/merchants_controller.rb`
- Create: `app/views/merchants/edit.html.erb`
- Modify: `config/routes.rb`
- Modify: `config/locales/en.yml`
- Modify: `spec/requests/merchants_spec.rb` (or create if absent)

> **Context:** `decent_exposure` is already installed (Task 1). `expose(:merchant)` declares a lazy accessor method `merchant` on the controller. No `@merchant` needed — views call `merchant` directly.

- [ ] **Step 1: Write failing request specs**

Check if `spec/requests/merchants_spec.rb` exists:

```bash
ls spec/requests/
```

If it exists, open it and add the following context blocks. If it doesn't exist, create it with this full content:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Merchants", type: :request do
  let_it_be(:psp_admin)      { create(:user, :psp_admin) }
  let_it_be(:merchant_admin) { create(:user, :merchant_admin, merchant_id: "merch_abc") }
  let_it_be(:merchant_viewer){ create(:user, :merchant_viewer, merchant_id: "merch_abc") }
  let_it_be(:other_admin)    { create(:user, :merchant_admin, merchant_id: "merch_xyz") }

  let_it_be(:merchant_abc) { create(:merchant, merchant_id: "merch_abc", name: "Acme Corp") }
  let_it_be(:merchant_xyz) { create(:merchant, merchant_id: "merch_xyz", name: "XYZ Ltd") }

  describe "GET /merchants/:id/edit" do
    context "when signed in as merchant_admin (own merchant)" do
      before { sign_in merchant_admin }

      it "returns 200" do
        get edit_merchant_path(merchant_abc)
        expect(response).to have_http_status(:ok)
      end
    end

    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "returns 200 for any merchant" do
        get edit_merchant_path(merchant_xyz)
        expect(response).to have_http_status(:ok)
      end
    end

    context "when signed in as merchant_admin (other merchant)" do
      before { sign_in merchant_admin }

      it "returns 403" do
        get edit_merchant_path(merchant_xyz)
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "returns 403" do
        get edit_merchant_path(merchant_abc)
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when unauthenticated" do
      it "redirects to sign in" do
        get edit_merchant_path(merchant_abc)
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "PATCH /merchants/:id" do
    context "when signed in as merchant_admin (own merchant)" do
      before { sign_in merchant_admin }

      it "updates profile and redirects to show" do
        patch merchant_path(merchant_abc), params: {
          merchant: { contact_email: "billing@acme.com", city: "London", country_code: "GB" }
        }
        expect(response).to redirect_to(merchant_path(merchant_abc))
        expect(merchant_abc.reload.contact_email).to eq("billing@acme.com")
      end

      it "re-renders edit with 422 on invalid email" do
        patch merchant_path(merchant_abc), params: {
          merchant: { contact_email: "not-an-email" }
        }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when signed in as merchant_admin (other merchant)" do
      before { sign_in merchant_admin }

      it "returns 403" do
        patch merchant_path(merchant_xyz), params: { merchant: { city: "London" } }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
```

- [ ] **Step 2: Run failing specs**

```bash
bin/rspec spec/requests/merchants_spec.rb --format documentation
```

Expected: FAIL — routing errors (no `edit_merchant_path` / `merchant_path` yet).

- [ ] **Step 3: Update routes**

Open `config/routes.rb` and change:

```ruby
resources :merchants, only: %i[new create]
```

to:

```ruby
resources :merchants, only: %i[new create index show edit update]
```

- [ ] **Step 4: Add i18n keys**

Open `config/locales/en.yml`. Find the `merchants:` key and add the `edit:` section. Also add to `flash.merchants:`:

```yaml
merchants:
  new:
    # (existing keys stay untouched)
  edit:
    page_title: "Edit merchant profile"
    title: "Edit merchant profile"
    subtitle: "Update contact and address details for this merchant."
    sections:
      contact: "Contact details"
      address: "Address"
    fields:
      contact_email: "Contact email"
      support_url: "Support URL"
      address_line1: "Address"
      city: "City"
      country_code: "Country code (ISO 3166-1 alpha-2, e.g. GB)"
    submit: "Save changes"
    cancel: "Cancel"

flash:
  merchants:
    # (existing keys stay)
    update_success: "Merchant profile updated."
```

- [ ] **Step 5: Implement controller edit/update actions**

Open `app/controllers/merchants_controller.rb`. Add `decent_exposure` and the new actions. The existing `new`, `create`, and private methods must not be changed. Add to the top of the class body (before `def new`):

```ruby
class MerchantsController < ApplicationController
  expose(:merchant) { Merchant.find_by!(merchant_id: params[:id]) }

  # PSP-admin onboarding: provision a merchant + first shop in tessera-core
  # (existing new/create stay below unchanged)
  def new
    authorize Tessera::Merchant, :new?, policy_class: MerchantPolicy
  end

  def create
    # ... existing unchanged ...
  end

  def edit
    authorize merchant, policy_class: MerchantPolicy
  end

  def update
    authorize merchant, policy_class: MerchantPolicy
    result = Merchants::UpdateProfile.call(merchant, merchant_profile_params)
    if result.errors.none?
      redirect_to merchant_path(merchant),
                  notice: t("flash.merchants.update_success")
    else
      flash.now[:alert] = result.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def merchant_profile_params
    params.fetch(:merchant, {}).permit(
      :contact_email, :support_url, :address_line1, :city, :country_code
    )
  end

  # ... (existing private methods: create_first_admin, onboarding_params_incomplete?, etc. stay) ...
end
```

Write out the full file — do not leave `# ... existing unchanged ...` placeholders. Read the current file first with `cat app/controllers/merchants_controller.rb` and produce the complete replacement.

- [ ] **Step 6: Create the edit view**

Create `app/views/merchants/edit.html.erb`:

```erb
<% content_for :title, t('.page_title') %>

<div class="max-w-2xl">
  <div class="mb-6">
    <%= link_to t('.cancel'), merchant_path(merchant),
          class: "text-theme-sm font-medium text-brand-600 hover:text-brand-700" %>
  </div>

  <div class="mb-6">
    <h1 class="text-xl font-semibold text-gray-900"><%= t('.title') %></h1>
    <p class="mt-0.5 text-theme-sm text-gray-500"><%= t('.subtitle') %></p>
  </div>

  <% if flash[:alert] %>
    <div class="mb-4 rounded-md bg-red-50 p-4 text-theme-sm text-red-700">
      <%= flash[:alert] %>
    </div>
  <% end %>

  <div class="card">
    <%= form_with url: merchant_path(merchant), method: :patch, class: "space-y-6" do |f| %>

      <section class="space-y-4">
        <h2 class="text-xs font-semibold uppercase tracking-wider text-gray-500">
          <%= t('.sections.contact') %>
        </h2>

        <div>
          <%= label_tag "merchant[contact_email]", t('.fields.contact_email'), class: "form-label" %>
          <%= email_field_tag "merchant[contact_email]",
                params.dig(:merchant, :contact_email) || merchant.contact_email,
                class: "form-input mt-1" %>
        </div>

        <div>
          <%= label_tag "merchant[support_url]", t('.fields.support_url'), class: "form-label" %>
          <%= url_field_tag "merchant[support_url]",
                params.dig(:merchant, :support_url) || merchant.support_url,
                placeholder: "https://your-site.com/support",
                class: "form-input mt-1" %>
        </div>
      </section>

      <section class="space-y-4 border-t border-gray-200 pt-6">
        <h2 class="text-xs font-semibold uppercase tracking-wider text-gray-500">
          <%= t('.sections.address') %>
        </h2>

        <div>
          <%= label_tag "merchant[address_line1]", t('.fields.address_line1'), class: "form-label" %>
          <%= text_field_tag "merchant[address_line1]",
                params.dig(:merchant, :address_line1) || merchant.address_line1,
                class: "form-input mt-1" %>
        </div>

        <div>
          <%= label_tag "merchant[city]", t('.fields.city'), class: "form-label" %>
          <%= text_field_tag "merchant[city]",
                params.dig(:merchant, :city) || merchant.city,
                class: "form-input mt-1" %>
        </div>

        <div>
          <%= label_tag "merchant[country_code]", t('.fields.country_code'), class: "form-label" %>
          <%= text_field_tag "merchant[country_code]",
                params.dig(:merchant, :country_code) || merchant.country_code,
                maxlength: 2, placeholder: "GB",
                class: "form-input mt-1 w-24" %>
        </div>
      </section>

      <div class="flex flex-col gap-3 border-t border-gray-200 pt-6 sm:flex-row">
        <%= f.submit t('.submit'), class: "btn-primary w-full sm:w-auto" %>
        <%= link_to t('.cancel'), merchant_path(merchant),
              class: "btn-secondary w-full sm:w-auto" %>
      </div>

    <% end %>
  </div>
</div>
```

- [ ] **Step 7: Run request specs**

```bash
bin/rspec spec/requests/merchants_spec.rb --format documentation
```

Expected: all `edit` and `update` examples PASS.

- [ ] **Step 8: Full suite**

```bash
bin/rspec --format progress
```

Expected: 0 failures.

- [ ] **Step 9: Commit**

```bash
git add app/controllers/merchants_controller.rb \
        app/views/merchants/edit.html.erb \
        config/routes.rb \
        config/locales/en.yml \
        spec/requests/merchants_spec.rb
git commit -m "MH-40: merchant profile edit/update (controller, view, routes, i18n)"
```

---

## Task 7: Shop display_name — model, service, controller, view, specs (MH-42)

**Files:**
- Modify: `app/models/shop.rb`
- Create: `app/services/shops/update_settings.rb`
- Modify: `app/controllers/shops_controller.rb`
- Modify: `app/views/shops/edit.html.erb`
- Modify: `config/locales/en.yml`
- Create: `spec/services/shops/update_settings_spec.rb`
- Modify: `spec/requests/shops_spec.rb`

> **Context:** `notification_url` and `test_mode` already exist in the schema and shop edit form. This task adds `display_name`, introduces `Shops::UpdateSettings` as the service behind the form, and updates the controller to use it instead of `ControlPlane::ShopConfigStore`. `ShopConfigStore` is **not deleted** — it stays in place.

- [ ] **Step 1: Write failing service spec**

Create `spec/services/shops/update_settings_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Shops::UpdateSettings do
  let(:shop) { create(:shop, notification_url: nil, test_mode: false, display_name: nil) }

  describe ".call" do
    it "updates display_name, notification_url, and test_mode" do
      result = described_class.call(shop, {
        display_name: "My Store",
        notification_url: "https://example.com/hook",
        test_mode: "1"
      })

      expect(result.errors).to be_empty
      reloaded = shop.reload
      expect(reloaded.display_name).to eq("My Store")
      expect(reloaded.notification_url).to eq("https://example.com/hook")
      expect(reloaded.test_mode).to be true
    end

    it "casts test_mode string '0' to false" do
      shop.update!(test_mode: true)
      described_class.call(shop, { test_mode: "0" })
      expect(shop.reload.test_mode).to be false
    end

    it "returns shop with errors when notification_url is not HTTPS" do
      result = described_class.call(shop, { notification_url: "http://insecure.com/hook" })
      expect(result.errors[:notification_url]).to be_present
    end

    it "does not update unpermitted fields (e.g. shop_id)" do
      original_id = shop.shop_id
      described_class.call(shop, { shop_id: "hacked" })
      expect(shop.reload.shop_id).to eq(original_id)
    end
  end
end
```

- [ ] **Step 2: Run failing spec**

```bash
bin/rspec spec/services/shops/update_settings_spec.rb --format documentation
```

Expected: FAIL — `uninitialized constant Shops::UpdateSettings`.

- [ ] **Step 3: Add notification_url validation to Shop model**

Open `app/models/shop.rb`. Add after the existing `validates :name` line:

```ruby
HTTPS_REGEXP = /\Ahttps:\/\//i
private_constant :HTTPS_REGEXP

validates :notification_url,
  format: { with: HTTPS_REGEXP, message: "must be an HTTPS URL" },
  allow_blank: true
```

Full `app/models/shop.rb` after edit:

```ruby
# frozen_string_literal: true

# MerchantHub-owned shop / storefront. Links to tessera-core via integration_account_id.
class Shop < ApplicationRecord
  HTTPS_REGEXP = /\Ahttps:\/\//i
  private_constant :HTTPS_REGEXP

  belongs_to :merchant,
    foreign_key: :merchant_id,
    primary_key: :merchant_id,
    inverse_of: :shops,
    optional: true

  scope :for_merchant, ->(merchant_id) { where(merchant_id: merchant_id) }

  validates :shop_id, presence: true, uniqueness: true
  validates :merchant_id, presence: true
  validates :integration_account_id, presence: true
  validates :name, presence: true
  validates :notification_url,
    format: { with: HTTPS_REGEXP, message: "must be an HTTPS URL" },
    allow_blank: true

  def to_param
    shop_id
  end
end
```

- [ ] **Step 4: Implement Shops::UpdateSettings**

Create `app/services/shops/update_settings.rb`:

```ruby
# frozen_string_literal: true

module Shops
  class UpdateSettings
    PERMITTED = %i[display_name notification_url test_mode].freeze
    private_constant :PERMITTED

    def self.call(shop, params) = new(shop, params).call

    def initialize(shop, params)
      @shop   = shop
      @params = params.to_h.symbolize_keys.slice(*PERMITTED)
      if @params.key?(:test_mode)
        @params[:test_mode] = ActiveModel::Type::Boolean.new.cast(@params[:test_mode])
      end
    end

    def call
      @shop.update(@params)
      @shop
    end
  end
end
```

- [ ] **Step 5: Run service specs**

```bash
bin/rspec spec/services/shops/update_settings_spec.rb --format documentation
```

Expected: all PASS.

- [ ] **Step 6: Update ShopsController#update**

Open `app/controllers/shops_controller.rb`. Replace the `update` method and `shop_update_params` private method. Read the full file first (`cat app/controllers/shops_controller.rb`) and produce the complete replacement with only these two methods changed:

```ruby
def update
  @shop = Tessera::Shop.find_by!(shop_id: params[:id])
  authorize @shop, :update?, policy_class: ShopPolicy

  result = Shops::UpdateSettings.call(@shop, shop_update_params)
  if result.errors.none?
    redirect_to shop_path(@shop), notice: I18n.t("flash.shops.update_success")
  else
    flash.now[:alert] = result.errors.full_messages.to_sentence
    render :edit, status: :unprocessable_entity
  end
end
```

```ruby
def shop_update_params
  params.fetch(:shop, {}).permit(:display_name, :notification_url, :test_mode)
end
```

- [ ] **Step 7: Update the shop edit view**

Open `app/views/shops/edit.html.erb`. Add a `display_name` field as the first field inside the card form, before the `notification_url` div:

```erb
<div>
  <%= label_tag "shop[display_name]", t('.fields.display_name'), class: "form-label" %>
  <p class="text-xs text-gray-500 mt-0.5"><%= t('.fields.display_name_hint') %></p>
  <%= text_field_tag "shop[display_name]",
        params.dig(:shop, :display_name) || @shop.display_name,
        placeholder: @shop.name,
        class: "form-input mt-1" %>
</div>
```

- [ ] **Step 8: Add i18n keys for shop edit**

In `config/locales/en.yml`, find `shops.edit.fields` and add:

```yaml
shops:
  edit:
    fields:
      display_name: "Display name"
      display_name_hint: "Optional friendly name shown in the portal. Defaults to the shop name when blank."
      # (existing notification_url, test_mode keys stay)
```

- [ ] **Step 9: Update shops request spec**

Open `spec/requests/shops_spec.rb`. Find the context `"when core returns an error"` inside `describe "PATCH /shops/:id"` and replace it:

```ruby
context "when notification_url is not HTTPS" do
  before { sign_in merchant_admin }

  it "re-renders edit with 422" do
    patch shop_path(own_shop), params: {
      shop: { notification_url: "http://insecure.com/hook" }
    }
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
```

Also add a `display_name` update example inside the `"when merchant_admin updates own shop"` context:

```ruby
it "updates display_name and redirects" do
  patch shop_path(own_shop), params: {
    shop: { display_name: "Flagship Store" }
  }
  expect(response).to redirect_to(shop_path(own_shop))
  expect(own_shop.reload.display_name).to eq("Flagship Store")
end
```

- [ ] **Step 10: Run shop specs**

```bash
bin/rspec spec/requests/shops_spec.rb --format documentation
```

Expected: all PASS.

- [ ] **Step 11: Full suite**

```bash
bin/rspec --format progress
```

Expected: 0 failures.

- [ ] **Step 12: Commit**

```bash
git add app/models/shop.rb \
        app/services/shops/update_settings.rb \
        app/controllers/shops_controller.rb \
        app/views/shops/edit.html.erb \
        config/locales/en.yml \
        spec/services/shops/update_settings_spec.rb \
        spec/requests/shops_spec.rb
git commit -m "MH-42: shop display_name — UpdateSettings service, model validation, controller, view"
```

---

## Task 8: Merchant index + show (MH-41)

**Files:**
- Modify: `app/controllers/merchants_controller.rb`
- Create: `app/views/merchants/index.html.erb`
- Create: `app/views/merchants/show.html.erb`
- Modify: `config/locales/en.yml`
- Modify: `spec/requests/merchants_spec.rb`

> **Context:** Routes already include `index` and `show` from Task 6. `decent_exposure` is installed. The controller already has `expose(:merchant)` — we add `expose(:merchants)` for the index. Pagy is used via `pagy(:offset, scope, ...)` — see `PaymentsController` for the pattern. The search input submits via GET using Turbo Frame; reuse the existing `FilterController` Stimulus controller for debounced submit.

- [ ] **Step 1: Write failing request specs**

Open `spec/requests/merchants_spec.rb` and add these contexts after the existing `edit`/`update` describes:

```ruby
describe "GET /merchants" do
  context "when signed in as psp_admin" do
    before { sign_in psp_admin }

    it "returns 200 and lists all merchants" do
      get merchants_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Acme Corp")
      expect(response.body).to include("XYZ Ltd")
    end

    it "filters by name query" do
      get merchants_path, params: { q: "Acme" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Acme Corp")
      expect(response.body).not_to include("XYZ Ltd")
    end

    it "filters by merchant_id query" do
      get merchants_path, params: { q: "merch_xyz" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("XYZ Ltd")
      expect(response.body).not_to include("Acme Corp")
    end
  end

  context "when signed in as psp_support" do
    before { sign_in psp_support }

    it "returns 200" do
      get merchants_path
      expect(response).to have_http_status(:ok)
    end
  end

  context "when signed in as merchant_admin" do
    before { sign_in merchant_admin }

    it "returns 403" do
      get merchants_path
      expect(response).to have_http_status(:forbidden)
    end
  end

  context "when unauthenticated" do
    it "redirects to sign in" do
      get merchants_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end

describe "GET /merchants/:id" do
  context "when signed in as psp_admin" do
    before { sign_in psp_admin }

    it "returns 200 for any merchant" do
      get merchant_path(merchant_abc)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Acme Corp")
    end
  end

  context "when signed in as psp_support" do
    before { sign_in psp_support }

    it "returns 200" do
      get merchant_path(merchant_abc)
      expect(response).to have_http_status(:ok)
    end
  end

  context "when signed in as merchant_admin (own merchant)" do
    before { sign_in merchant_admin }

    it "returns 200" do
      get merchant_path(merchant_abc)
      expect(response).to have_http_status(:ok)
    end
  end

  context "when signed in as merchant_admin (other merchant)" do
    before { sign_in merchant_admin }

    it "returns 403" do
      get merchant_path(merchant_xyz)
      expect(response).to have_http_status(:forbidden)
    end
  end

  context "when signed in as merchant_viewer" do
    before { sign_in merchant_viewer }

    it "returns 403" do
      get merchant_path(merchant_abc)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
```

Also add `psp_support` to the `let_it_be` block at the top of the spec if not already present:

```ruby
let_it_be(:psp_support) { create(:user, :psp_support) }
```

- [ ] **Step 2: Run failing specs**

```bash
bin/rspec spec/requests/merchants_spec.rb -e "GET /merchants" --format documentation
```

Expected: FAIL — controller actions not yet implemented.

- [ ] **Step 3: Add index and show to the controller**

Open `app/controllers/merchants_controller.rb`. Read the full file first. Add `expose(:merchants)` and the `index`/`show` action methods. Full file with all additions:

```ruby
class MerchantsController < ApplicationController
  expose(:merchants) {
    scope = policy_scope(Merchant, policy_scope_class: MerchantPolicy::Scope)
    if params[:q].present?
      q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
      scope = scope.where("name ILIKE :q OR merchant_id ILIKE :q", q: q)
    end
    scope.order(:name)
  }

  expose(:merchant) { Merchant.find_by!(merchant_id: params[:id]) }

  def index
    authorize Merchant, :index?, policy_class: MerchantPolicy
    @pagy, @merchants = pagy(:offset, merchants)
  end

  def show
    authorize merchant, :show?, policy_class: MerchantPolicy
    @shops = Shop.for_merchant(merchant.merchant_id).order(:name)
    @users = User.where(merchant_id: merchant.merchant_id).order(:email)
  end

  def new
    authorize Tessera::Merchant, :new?, policy_class: MerchantPolicy
  end

  def create
    # ... (existing create action unchanged) ...
  end

  def edit
    authorize merchant, policy_class: MerchantPolicy
  end

  def update
    authorize merchant, policy_class: MerchantPolicy
    result = Merchants::UpdateProfile.call(merchant, merchant_profile_params)
    if result.errors.none?
      redirect_to merchant_path(merchant),
                  notice: t("flash.merchants.update_success")
    else
      flash.now[:alert] = result.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def merchant_profile_params
    params.fetch(:merchant, {}).permit(
      :contact_email, :support_url, :address_line1, :city, :country_code
    )
  end

  # (existing private methods stay: create_first_admin, etc.)
end
```

**Important:** Do not use `# ... (existing ... unchanged) ...` placeholders. Read the current file and produce the complete replacement.

- [ ] **Step 4: Add i18n keys for index and show**

In `config/locales/en.yml`, add under `merchants:`:

```yaml
merchants:
  index:
    page_title: "Merchants"
    title: "Merchants"
    search_placeholder: "Search by name or ID…"
    table:
      name: "Name"
      merchant_id: "Merchant ID"
      shops: "Shops"
      created: "Created"
      empty: "No merchants found."
  show:
    sections:
      profile: "Profile"
      shops: "Shops"
      team: "Team"
    fields:
      merchant_id: "Merchant ID"
      contact_email: "Contact email"
      support_url: "Support URL"
      address: "Address"
      country_code: "Country"
      name: "Name"
    table:
      shop_name: "Shop"
      shop_id: "Shop ID"
      test_mode: "Mode"
      notification_url: "Webhook URL"
      email: "Email"
      role: "Role"
      status: "Status"
      last_sign_in: "Last sign-in"
      never: "Never"
      test: "Test"
      live: "Live"
      active: "Active"
      locked: "Locked"
    edit_profile: "Edit profile"
    back: "← Back to merchants"
```

- [ ] **Step 5: Create the index view**

Create `app/views/merchants/index.html.erb`:

```erb
<% content_for :title, t('.page_title') %>

<div class="mb-6 flex items-center justify-between">
  <h1 class="text-xl font-semibold text-gray-900"><%= t('.title') %></h1>
</div>

<div class="card">
  <%# Toolbar: search %>
  <%= form_with url: merchants_path, method: :get,
        data: { controller: "filter", turbo_frame: "merchants-table" },
        class: "mb-4" do %>
    <div class="flex items-center gap-3">
      <div class="relative flex-1 max-w-sm">
        <input type="search" name="q" value="<%= params[:q] %>"
               placeholder="<%= t('.search_placeholder') %>"
               class="form-input pl-9"
               data-action="input->filter#submitDebounced" />
        <span class="pointer-events-none absolute inset-y-0 left-3 flex items-center text-gray-400">
          <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                  d="M21 21l-4.35-4.35M17 11A6 6 0 1 1 5 11a6 6 0 0 1 12 0z"/>
          </svg>
        </span>
      </div>
    </div>
  <% end %>

  <%= turbo_frame_tag "merchants-table" do %>
    <table class="w-full text-left text-theme-sm">
      <thead>
        <tr class="border-b border-gray-200">
          <th class="py-3 pr-4 font-medium text-gray-500 border-r border-gray-100"><%= t('.table.name') %></th>
          <th class="px-4 py-3 font-medium text-gray-500 border-r border-gray-100"><%= t('.table.merchant_id') %></th>
          <th class="px-4 py-3 font-medium text-gray-500 border-r border-gray-100"><%= t('.table.shops') %></th>
          <th class="px-4 py-3 font-medium text-gray-500"><%= t('.table.created') %></th>
        </tr>
      </thead>
      <tbody class="divide-y divide-gray-100">
        <% if @merchants.empty? %>
          <tr>
            <td colspan="4" class="py-10 text-center text-theme-sm text-gray-500">
              <%= t('.table.empty') %>
            </td>
          </tr>
        <% else %>
          <% @merchants.each do |m| %>
            <tr class="hover:bg-gray-50">
              <td class="py-3 pr-4 font-medium text-gray-900 border-r border-gray-100">
                <%= link_to m.name, merchant_path(m),
                      class: "text-brand-600 hover:text-brand-700 hover:underline" %>
              </td>
              <td class="px-4 py-3 font-mono text-xs text-gray-600 border-r border-gray-100">
                <%= m.merchant_id %>
              </td>
              <td class="px-4 py-3 text-gray-600 border-r border-gray-100">
                <%= m.shops.size %>
              </td>
              <td class="px-4 py-3 text-gray-500">
                <%= m.created_at.strftime("%d %b %Y") %>
              </td>
            </tr>
          <% end %>
        <% end %>
      </tbody>
    </table>

    <%# Pagy footer %>
    <% if @pagy.pages > 1 %>
      <div class="mt-4 border-t border-gray-200 pt-4">
        <%== pagy_nav(@pagy) %>
      </div>
    <% end %>
  <% end %>
</div>
```

- [ ] **Step 6: Create the show view**

Create `app/views/merchants/show.html.erb`:

```erb
<% content_for :title, merchant.name %>

<div class="mb-4">
  <%= link_to t('.back'), merchants_path,
        class: "text-theme-sm font-medium text-brand-600 hover:text-brand-700" %>
</div>

<div class="mb-6 flex items-start justify-between">
  <div>
    <h1 class="text-xl font-semibold text-gray-900"><%= merchant.name %></h1>
    <p class="mt-0.5 text-theme-sm font-mono text-gray-400"><%= merchant.merchant_id %></p>
  </div>
  <% if policy(merchant, policy_class: MerchantPolicy).edit? %>
    <%= link_to t('.edit_profile'), edit_merchant_path(merchant),
          class: "btn-secondary text-theme-sm" %>
  <% end %>
</div>

<%# Profile card %>
<div class="card mb-6">
  <h2 class="mb-4 text-xs font-semibold uppercase tracking-wider text-gray-500">
    <%= t('.sections.profile') %>
  </h2>
  <dl class="grid grid-cols-1 gap-3 sm:grid-cols-2 text-theme-sm">
    <% if merchant.contact_email.present? %>
      <div>
        <dt class="font-medium text-gray-500"><%= t('.fields.contact_email') %></dt>
        <dd class="text-gray-900"><%= merchant.contact_email %></dd>
      </div>
    <% end %>
    <% if merchant.support_url.present? %>
      <div>
        <dt class="font-medium text-gray-500"><%= t('.fields.support_url') %></dt>
        <dd class="text-gray-900">
          <%= link_to merchant.support_url, merchant.support_url,
                target: "_blank", rel: "noopener",
                class: "text-brand-600 hover:underline" %>
        </dd>
      </div>
    <% end %>
    <% if merchant.address_line1.present? || merchant.city.present? %>
      <div>
        <dt class="font-medium text-gray-500"><%= t('.fields.address') %></dt>
        <dd class="text-gray-900">
          <%= [ merchant.address_line1, merchant.city, merchant.country_code ].compact_blank.join(", ") %>
        </dd>
      </div>
    <% end %>
  </dl>
</div>

<%# Shops table %>
<div class="card mb-6">
  <h2 class="mb-4 text-xs font-semibold uppercase tracking-wider text-gray-500">
    <%= t('.sections.shops') %>
  </h2>
  <table class="w-full text-left text-theme-sm">
    <thead>
      <tr class="border-b border-gray-200">
        <th class="py-2 pr-4 font-medium text-gray-500 border-r border-gray-100"><%= t('.table.shop_name') %></th>
        <th class="px-4 py-2 font-medium text-gray-500 border-r border-gray-100"><%= t('.table.shop_id') %></th>
        <th class="px-4 py-2 font-medium text-gray-500 border-r border-gray-100"><%= t('.table.test_mode') %></th>
        <th class="px-4 py-2 font-medium text-gray-500"><%= t('.table.notification_url') %></th>
      </tr>
    </thead>
    <tbody class="divide-y divide-gray-100">
      <% @shops.each do |shop| %>
        <tr class="hover:bg-gray-50">
          <td class="py-2 pr-4 font-medium text-gray-900 border-r border-gray-100">
            <%= link_to shop.display_name.presence || shop.name, shop_path(shop),
                  class: "text-brand-600 hover:underline" %>
          </td>
          <td class="px-4 py-2 font-mono text-xs text-gray-600 border-r border-gray-100">
            <%= shop.shop_id %>
          </td>
          <td class="px-4 py-2 border-r border-gray-100">
            <% if shop.test_mode? %>
              <span class="inline-flex items-center rounded-full bg-yellow-100 px-2 py-0.5 text-xs font-medium text-yellow-700">
                <%= t('.table.test') %>
              </span>
            <% else %>
              <span class="inline-flex items-center rounded-full bg-green-100 px-2 py-0.5 text-xs font-medium text-green-700">
                <%= t('.table.live') %>
              </span>
            <% end %>
          </td>
          <td class="px-4 py-2 text-gray-500 text-xs truncate max-w-xs">
            <%= shop.notification_url.presence || "—" %>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
</div>

<%# Team table %>
<div class="card">
  <h2 class="mb-4 text-xs font-semibold uppercase tracking-wider text-gray-500">
    <%= t('.sections.team') %>
  </h2>
  <table class="w-full text-left text-theme-sm">
    <thead>
      <tr class="border-b border-gray-200">
        <th class="py-2 pr-4 font-medium text-gray-500 border-r border-gray-100"><%= t('.table.email') %></th>
        <th class="px-4 py-2 font-medium text-gray-500 border-r border-gray-100"><%= t('.table.role') %></th>
        <th class="px-4 py-2 font-medium text-gray-500 border-r border-gray-100"><%= t('.table.status') %></th>
        <th class="px-4 py-2 font-medium text-gray-500"><%= t('.table.last_sign_in') %></th>
      </tr>
    </thead>
    <tbody class="divide-y divide-gray-100">
      <% @users.each do |u| %>
        <tr>
          <td class="py-2 pr-4 text-gray-900 border-r border-gray-100"><%= u.email %></td>
          <td class="px-4 py-2 text-gray-600 border-r border-gray-100"><%= u.role.humanize %></td>
          <td class="px-4 py-2 border-r border-gray-100">
            <% if u.access_locked? %>
              <span class="inline-flex items-center rounded-full bg-red-100 px-2 py-0.5 text-xs font-medium text-red-700">
                <%= t('.table.locked') %>
              </span>
            <% else %>
              <span class="inline-flex items-center rounded-full bg-green-100 px-2 py-0.5 text-xs font-medium text-green-700">
                <%= t('.table.active') %>
              </span>
            <% end %>
          </td>
          <td class="px-4 py-2 text-gray-500">
            <%= u.last_sign_in_at&.strftime("%d %b %Y") || t('.table.never') %>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
</div>
```

- [ ] **Step 7: Run merchant request specs**

```bash
bin/rspec spec/requests/merchants_spec.rb --format documentation
```

Expected: all examples PASS.

- [ ] **Step 8: Full suite**

```bash
bin/rspec --format progress
```

Expected: 0 failures.

- [ ] **Step 9: RuboCop**

```bash
bin/rubocop --autocorrect
```

Fix any remaining offenses manually. Re-run until clean.

- [ ] **Step 10: Commit**

```bash
git add app/controllers/merchants_controller.rb \
        app/views/merchants/index.html.erb \
        app/views/merchants/show.html.erb \
        config/locales/en.yml \
        spec/requests/merchants_spec.rb
git commit -m "MH-41: merchant index and show (PSP admin browse, per-merchant detail)"
```

---

## Self-review

**Spec coverage:**

| Requirement | Task |
|---|---|
| Migration: merchant profile fields | Task 2 |
| Migration: shop display_name | Task 3 |
| Merchant model validations (email, country_code) | Task 4 |
| `Merchants::UpdateProfile` service | Task 4 |
| `MerchantPolicy` full CRUD + Scope | Task 5 |
| Routes: merchants index/show/edit/update | Task 6 |
| `MerchantsController` edit/update | Task 6 |
| `merchants/edit.html.erb` | Task 6 |
| `Shops::UpdateSettings` service | Task 7 |
| Shop model notification_url validation | Task 7 |
| `ShopsController#update` uses service | Task 7 |
| Shop edit view adds display_name field | Task 7 |
| `MerchantsController` index/show | Task 8 |
| `merchants/index.html.erb` with Turbo Frame search | Task 8 |
| `merchants/show.html.erb` with shops + team | Task 8 |
| Request specs: merchants edit/update | Task 6 |
| Request specs: merchants index/show | Task 8 |
| Request specs: shops display_name + HTTPS validation | Task 7 |
| `decent_exposure` gem | Task 1 |

**Placeholder scan:** No TBDs or "similar to Task N" references. Every code block is complete.

**Type consistency:**
- `Merchants::UpdateProfile.call(merchant, params)` — consistent across Task 4 spec, Task 4 impl, Task 6 controller.
- `Shops::UpdateSettings.call(shop, params)` — consistent across Task 7 spec, Task 7 impl, Task 7 controller.
- `expose(:merchant)` uses `Merchant.find_by!(merchant_id: params[:id])` — consistent with `merchant_path(merchant)` which uses `to_param`. Note: `Merchant` does not define `to_param`, so it defaults to `id` (the UUID). **Fix needed:** either add `def to_param = merchant_id` to `Merchant`, or use `merchant_path(merchant.merchant_id)` everywhere.

**Fix applied:** Add `to_param` to `Merchant` model in Task 4 Step 3:

```ruby
def to_param
  merchant_id
end
```

This makes `merchant_path(merchant)` generate `/merchants/merch_abc` (matching the `find_by!(merchant_id:)` lookup in `expose(:merchant)`).
