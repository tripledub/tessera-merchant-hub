# MH-29: Merchant & Shop Profile Management Design

**Stories covered:** MH-40 (merchant profile edit), MH-42 (shop settings edit — display_name), MH-41 (PSP admin merchant browse & show)

**Goal:** Allow merchant admins to edit their merchant profile and shop settings; give PSP admins a searchable merchant directory with a per-merchant detail page.

**Architecture:** Thin controllers using `decent_exposure` (new actions only) delegating mutations to service objects. AR models own validations. Pundit policies own access rules. No raw SQL for MH-owned fields.

**Tech Stack:** Rails 8, Hotwire (Turbo Frames for search), Pundit, Pagy, `decent_exposure` gem, RSpec request specs.

**Implementation order:** MH-40 → MH-42 → MH-41

---

## Data model changes

### MH-40 — `merchants` table

New columns (all nullable strings unless noted):

| Column | Type | Notes |
|---|---|---|
| `contact_email` | string | validated format if present |
| `support_url` | string | optional |
| `address_line1` | string | optional |
| `city` | string | optional |
| `country_code` | string | ISO 3166-1 alpha-2; validated format if present |

Existing `country` column is left untouched (used by onboarding flow).

### MH-42 — `shops` table

| Column | Type | Notes |
|---|---|---|
| `display_name` | string | nullable; UI falls back to `name` when blank |

`notification_url` and `test_mode` already exist in the schema — no migration needed for them.

---

## Gem addition

Add `decent_exposure` to the `Gemfile` (no group restriction — used in controllers).

Used only in new `MerchantsController` actions. Existing controllers (`ShopsController`, `PaymentsController`) are not changed.

---

## MH-40: Merchant profile edit

### Model — `app/models/merchant.rb`

Add validations for new fields:

```ruby
validates :contact_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
validates :country_code,  format: { with: /\A[A-Z]{2}\z/ }, allow_blank: true
```

### Service — `app/services/merchants/update_profile.rb`

```ruby
module Merchants
  class UpdateProfile
    PERMITTED = %i[contact_email support_url address_line1 city country_code].freeze

    def self.call(merchant, params) = new(merchant, params).call

    def initialize(merchant, params)
      @merchant = merchant
      @params   = params.slice(*PERMITTED)
    end

    def call
      @merchant.update(@params)
      @merchant
    end
  end
end
```

Returns the merchant record; callers check `merchant.errors.any?`.

### Policy — `app/policies/merchant_policy.rb`

Replace the headless onboarding-only policy:

```ruby
class MerchantPolicy < ApplicationPolicy
  def new?    = psp_admin?
  def create? = psp_admin?
  def index?  = psp_role?
  def show?   = psp_role? || own_merchant?
  def edit?   = psp_admin? || (merchant_admin? && own_merchant?)
  def update? = edit?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user.psp_role?
      return scope.where(merchant_id: user.merchant_id) if user.merchant_admin?
      scope.none
    end
  end

  private

  def own_merchant?
    user.merchant_id.present? && user.merchant_id == record.merchant_id
  end
end
```

`record` will be a `Merchant` AR instance for `show`/`edit`/`update`. For `index`, `new`, `create` it is the class — `own_merchant?` is never called for those.

### Controller — `app/controllers/merchants_controller.rb`

Add `decent_exposure` and new actions. Existing `new`/`create` are unchanged.

```ruby
class MerchantsController < ApplicationController
  expose(:merchant) { Merchant.find_by!(merchant_id: params[:id]) }

  def edit
    authorize merchant, policy_class: MerchantPolicy
  end

  def update
    authorize merchant, policy_class: MerchantPolicy
    result = Merchants::UpdateProfile.call(merchant, merchant_params)
    if result.errors.none?
      redirect_to merchant_path(merchant), notice: t("flash.merchants.update_success")
    else
      flash.now[:alert] = result.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def merchant_params
    params.fetch(:merchant, {}).permit(:contact_email, :support_url, :address_line1, :city, :country_code)
  end
end
```

### Routes

```ruby
resources :merchants, only: %i[new create index show edit update]
```

### View — `app/views/merchants/edit.html.erb`

Card form, two sections: "Contact details" and "Address". Back link to `merchant_path`. Fields: `contact_email`, `support_url`, `address_line1`, `city`, `country_code`. Follows existing view patterns (form-label, form-input, btn-primary/btn-secondary). All i18n via `t('.fields.*')`.

### i18n additions — `config/locales/en.yml`

```yaml
merchants:
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
      country_code: "Country code (ISO)"
    submit: "Save changes"
    cancel: "Cancel"
flash:
  merchants:
    update_success: "Merchant profile updated."
    update_failed: "Could not save changes: %{errors}"
```

### Specs

**`spec/models/merchant_spec.rb`** — add examples for `contact_email` and `country_code` format validations (valid, blank, invalid).

**`spec/services/merchants/update_profile_spec.rb`** — new file covering: updates permitted fields, rejects invalid email, returns merchant with errors on failure, does not update unpermitted fields.

**`spec/requests/merchants_spec.rb`** — new file covering:
- `GET /merchants/:id/edit` — 200 for merchant_admin (own), 200 for psp_admin, 403 for merchant_admin (other), 403 for merchant_viewer, 302 for unauthenticated
- `PATCH /merchants/:id` — success redirects to show, invalid email re-renders 422, wrong merchant 403

---

## MH-42: Shop settings edit — display_name

### Service — `app/services/shops/update_settings.rb`

```ruby
module Shops
  class UpdateSettings
    PERMITTED = %i[display_name notification_url test_mode].freeze

    def self.call(shop, params) = new(shop, params).call

    def initialize(shop, params)
      @shop   = shop
      @params = params.slice(*PERMITTED)
      @params[:test_mode] = ActiveModel::Type::Boolean.new.cast(@params[:test_mode]) if @params.key?(:test_mode)
    end

    def call
      @shop.update(@params)
      @shop
    end
  end
end
```

### Model — `app/models/shop.rb`

Add validation:

```ruby
validates :notification_url,
  format: { with: URI::DEFAULT_PARSER.make_regexp(%w[https]) },
  allow_blank: true
```

(The URL format check was previously in the controller; move it to the model where it belongs.)

### Controller — `app/controllers/shops_controller.rb`

Replace the `update` action body:

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

private

def shop_update_params
  params.fetch(:shop, {}).permit(:display_name, :notification_url, :test_mode)
end
```

`ShopConfigStore` is left in place for any other callers (no other callers currently, but it is not deleted).

### View — `app/views/shops/edit.html.erb`

Add `display_name` field above `notification_url`:

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

### i18n additions

```yaml
shops:
  edit:
    fields:
      display_name: "Display name"
      display_name_hint: "Optional friendly name shown in the portal. Defaults to the shop name."
```

### Specs

**`spec/services/shops/update_settings_spec.rb`** — new file covering: updates all three fields, casts test_mode boolean, rejects invalid notification_url, returns shop with errors on failure.

**`spec/requests/shops_spec.rb`** — extend existing with: `display_name` update succeeds, invalid `notification_url` re-renders 422.

---

## MH-41: PSP admin merchant browse & show

### Controller — `app/controllers/merchants_controller.rb`

Add `index` and `show` using `decent_exposure`:

```ruby
expose(:merchants) {
  scope = policy_scope(Merchant, policy_scope_class: MerchantPolicy::Scope)
  scope = scope.where("name ILIKE :q OR merchant_id ILIKE :q", q: "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%") if params[:q].present?
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
```

### Views

**`app/views/merchants/index.html.erb`** — TailAdmin data table style:
- Toolbar: search input (Turbo Frame, debounced with FilterController or simple `data-action="input->filter#submitDebounced"`)
- Table columns: Name, Merchant ID, Shops, Created, (link to show)
- Turbo Frame `merchants-table` wrapping table + Pagy footer
- Empty state when no results
- Accessible to psp_role only (enforced by Pundit; merchant roles never reach this view)

**`app/views/merchants/show.html.erb`** — two sections:
1. **Profile card** — name, merchant_id, contact_email, support_url, address, country_code. Edit button for psp_admin/merchant_admin.
2. **Shops** — table: display_name (fallback to name), shop_id, test_mode badge, notification_url. Link to `shop_path`.
3. **Team** — table: email, role badge, status (active/locked), last sign-in. Read-only list; no actions (management is MH-27).

### i18n additions

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

### Specs

**`spec/requests/merchants_spec.rb`** — extend with:
- `GET /merchants` — 200 for psp_admin, 200 for psp_support, 302 redirect for merchant_admin, 302 for unauthenticated
- `GET /merchants?q=name` — returns matching merchants, excludes non-matching
- `GET /merchants/:id` — 200 for psp_admin, 200 for psp_support, 200 for merchant_admin (own), 403 for merchant_admin (other), 403 for merchant_viewer

---

## File summary

| Action | File |
|---|---|
| Create | `db/migrate/TIMESTAMP_add_profile_fields_to_merchants.rb` |
| Create | `db/migrate/TIMESTAMP_add_display_name_to_shops.rb` |
| Modify | `app/models/merchant.rb` |
| Modify | `app/models/shop.rb` |
| Create | `app/services/merchants/update_profile.rb` |
| Create | `app/services/shops/update_settings.rb` |
| Modify | `app/policies/merchant_policy.rb` |
| Modify | `app/controllers/merchants_controller.rb` |
| Modify | `app/controllers/shops_controller.rb` |
| Modify | `config/routes.rb` |
| Create | `app/views/merchants/edit.html.erb` |
| Create | `app/views/merchants/index.html.erb` |
| Create | `app/views/merchants/show.html.erb` |
| Modify | `app/views/shops/edit.html.erb` |
| Modify | `config/locales/en.yml` |
| Modify | `spec/models/merchant_spec.rb` |
| Create | `spec/services/merchants/update_profile_spec.rb` |
| Create | `spec/services/shops/update_settings_spec.rb` |
| Modify | `spec/requests/merchants_spec.rb` |
| Modify | `spec/requests/shops_spec.rb` |
| Modify | `Gemfile` / `Gemfile.lock` |
