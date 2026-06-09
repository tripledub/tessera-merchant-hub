# MH-27: User Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give merchant admins the ability to invite and deactivate their own team (`/team`), and give PSP admins a cross-merchant user directory with invite, unlock, and role-change (`/admin/users`).

**Architecture:** Two separate controllers (`TeamController`, `Admin::UsersController`) sharing `Users::Invite` and `Users::Deactivate` service objects. A new `deactivated_at` column distinguishes admin deactivation from Devise's automatic lockout. Invite emails reuse Devise's reset-password token with a customised mailer view. `decent_exposure` for skinny controllers; Pundit for authorisation; Pagy for pagination.

**Tech Stack:** Rails 8, Devise (lockable + recoverable), Pundit, Pagy, decent_exposure, letter_opener_web (development only), RSpec request + policy + service specs.

**Design spec:** `docs/superpowers/specs/2026-06-09-mh-27-user-management-design.md`

---

## File map

| Action | File |
|---|---|
| Create | `db/migrate/TIMESTAMP_add_deactivated_at_to_users.rb` |
| Modify | `app/models/user.rb` |
| Modify | `app/policies/user_policy.rb` |
| Create | `app/services/users/invite.rb` |
| Create | `app/services/users/deactivate.rb` |
| Create | `app/controllers/team_controller.rb` |
| Create | `app/controllers/admin/users_controller.rb` |
| Create | `app/views/team/index.html.erb` |
| Create | `app/views/team/new.html.erb` |
| Create | `app/views/admin/users/index.html.erb` |
| Create | `app/views/admin/users/new.html.erb` |
| Create | `app/views/devise/mailer/reset_password_instructions.html.erb` |
| Modify | `config/routes.rb` |
| Modify | `config/locales/en.yml` |
| Modify | `Gemfile` |
| Modify | `spec/models/user_spec.rb` |
| Create | `spec/services/users/invite_spec.rb` |
| Create | `spec/services/users/deactivate_spec.rb` |
| Modify | `spec/policies/user_policy_spec.rb` |
| Create | `spec/requests/team_spec.rb` |
| Create | `spec/requests/admin/users_spec.rb` |

---

## Task 1: Migration + User model (deactivated_at, scopes, Devise hooks)

**Files:**
- Create: `db/migrate/TIMESTAMP_add_deactivated_at_to_users.rb`
- Modify: `app/models/user.rb`
- Modify: `spec/models/user_spec.rb`

- [ ] **Step 1: Write failing model specs**

Add to `spec/models/user_spec.rb` after the existing `describe "roles"` block:

```ruby
describe "#deactivated?" do
  it "returns false when deactivated_at is nil" do
    user = build(:user, deactivated_at: nil)
    expect(user.deactivated?).to be false
  end

  it "returns true when deactivated_at is set" do
    user = build(:user, deactivated_at: 1.hour.ago)
    expect(user.deactivated?).to be true
  end
end

describe "#active_for_authentication?" do
  it "returns true for a normal active user" do
    user = build(:user, deactivated_at: nil)
    expect(user.active_for_authentication?).to be true
  end

  it "returns false when deactivated" do
    user = build(:user, deactivated_at: 1.hour.ago)
    expect(user.active_for_authentication?).to be false
  end
end

describe "#inactive_message" do
  it "returns :deactivated when deactivated" do
    user = build(:user, deactivated_at: 1.hour.ago)
    expect(user.inactive_message).to eq(:deactivated)
  end

  it "returns default Devise message when not deactivated" do
    user = build(:user, deactivated_at: nil)
    # Devise default inactive_message for a non-deactivated, non-locked user is :inactive
    expect(user.inactive_message).not_to eq(:deactivated)
  end
end

describe "scopes" do
  let!(:active_user)      { create(:user, deactivated_at: nil) }
  let!(:deactivated_user) { create(:user, deactivated_at: 1.hour.ago) }

  it ".active returns only non-deactivated users" do
    expect(User.active).to include(active_user)
    expect(User.active).not_to include(deactivated_user)
  end

  it ".deactivated returns only deactivated users" do
    expect(User.deactivated).to include(deactivated_user)
    expect(User.deactivated).not_to include(active_user)
  end
end
```

- [ ] **Step 2: Run specs to verify they fail**

```bash
bundle exec rspec spec/models/user_spec.rb --format documentation
```

Expected: failures referencing `deactivated_at`, `deactivated?`, `active_for_authentication?`

- [ ] **Step 3: Generate migration**

```bash
bundle exec rails generate migration AddDeactivatedAtToUsers deactivated_at:datetime
```

Check the generated file — it should look like:

```ruby
class AddDeactivatedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :deactivated_at, :datetime
    add_index :users, :deactivated_at
  end
end
```

Add the index manually if the generator didn't include it.

- [ ] **Step 4: Run migration**

```bash
bundle exec rails db:migrate
```

- [ ] **Step 5: Implement model changes**

Replace the full content of `app/models/user.rb`:

```ruby
class User < ApplicationRecord
  devise :database_authenticatable,
         :recoverable,
         :rememberable,
         :validatable,
         :trackable,
         :lockable

  enum :role, { psp_admin: 0, psp_support: 1, merchant_admin: 2, merchant_viewer: 3 }, default: :psp_admin

  scope :active,      -> { where(deactivated_at: nil) }
  scope :deactivated, -> { where.not(deactivated_at: nil) }

  validates :merchant_id, presence: true, if: :merchant_role?

  def psp_role?
    psp_admin? || psp_support?
  end

  def merchant_role?
    merchant_admin? || merchant_viewer?
  end

  def deactivated?
    deactivated_at.present?
  end

  # Devise hook — prevents sign-in for deactivated accounts regardless of password
  def active_for_authentication?
    super && !deactivated?
  end

  def inactive_message
    deactivated? ? :deactivated : super
  end

  # Shop business keys this user may access. PSP roles are unscoped (nil →
  # "all"); merchant roles see every shop under their merchant.
  def accessible_shop_ids
    return nil if psp_role?

    Tessera::Shop.for_merchant(merchant_id).pluck(:shop_id)
  end
end
```

- [ ] **Step 6: Run specs to verify they pass**

```bash
bundle exec rspec spec/models/user_spec.rb --format documentation
```

Expected: all examples pass

- [ ] **Step 7: Add deactivated Devise failure message to i18n**

In `config/locales/en.yml`, add under the top-level `en:` key (create a `devise:` section if it doesn't exist):

```yaml
devise:
  failure:
    deactivated: "Your account has been deactivated. Please contact your administrator."
```

- [ ] **Step 8: Commit**

```bash
git add db/migrate/ app/models/user.rb spec/models/user_spec.rb config/locales/en.yml
git commit -m "feat(MH-27): add deactivated_at to users with model scopes and Devise hooks"
```

---

## Task 2: UserPolicy — expand with invite, deactivate, unlock, update_role

**Files:**
- Modify: `app/policies/user_policy.rb`
- Modify: `spec/policies/user_policy_spec.rb`

**Context:** The existing `UserPolicy` has `index?`, `create?`, `update?`, `destroy?`, and `Scope`. We replace it with the new action set from the spec (`invite?`, `deactivate?`, `unlock?`, `update_role?`). The existing spec uses `pundit-matchers` `permit_action` / `forbid_action` helpers — follow that pattern.

- [ ] **Step 1: Write failing policy specs**

Replace the full content of `spec/policies/user_policy_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserPolicy, type: :policy do
  let(:psp_admin)       { build_stubbed(:user, :psp_admin) }
  let(:psp_support)     { build_stubbed(:user, :psp_support) }
  let(:merchant_admin)  { build_stubbed(:user, :merchant_admin, merchant_id: "m1") }
  let(:merchant_viewer) { build_stubbed(:user, :merchant_viewer, merchant_id: "m1") }

  let(:same_merchant_user)  { build_stubbed(:user, :merchant_viewer, merchant_id: "m1") }
  let(:other_merchant_user) { build_stubbed(:user, :merchant_viewer, merchant_id: "m2") }

  describe "index?" do
    it("permits psp_admin")      { expect(described_class.new(psp_admin, User)).to permit_action(:index) }
    it("permits merchant_admin") { expect(described_class.new(merchant_admin, User)).to permit_action(:index) }
    it("denies psp_support")     { expect(described_class.new(psp_support, User)).to forbid_action(:index) }
    it("denies merchant_viewer") { expect(described_class.new(merchant_viewer, User)).to forbid_action(:index) }
  end

  describe "invite?" do
    it("permits psp_admin")      { expect(described_class.new(psp_admin, User.new)).to permit_action(:invite) }
    it("permits merchant_admin") { expect(described_class.new(merchant_admin, User.new)).to permit_action(:invite) }
    it("denies psp_support")     { expect(described_class.new(psp_support, User.new)).to forbid_action(:invite) }
    it("denies merchant_viewer") { expect(described_class.new(merchant_viewer, User.new)).to forbid_action(:invite) }
  end

  describe "deactivate?" do
    it "permits psp_admin on any user" do
      expect(described_class.new(psp_admin, other_merchant_user)).to permit_action(:deactivate)
    end

    it "permits merchant_admin on same-merchant user" do
      expect(described_class.new(merchant_admin, same_merchant_user)).to permit_action(:deactivate)
    end

    it "denies merchant_admin on other-merchant user" do
      expect(described_class.new(merchant_admin, other_merchant_user)).to forbid_action(:deactivate)
    end

    it "denies merchant_admin deactivating themselves" do
      expect(described_class.new(merchant_admin, merchant_admin)).to forbid_action(:deactivate)
    end

    it "denies psp_admin deactivating themselves" do
      expect(described_class.new(psp_admin, psp_admin)).to forbid_action(:deactivate)
    end

    it "denies merchant_viewer" do
      expect(described_class.new(merchant_viewer, same_merchant_user)).to forbid_action(:deactivate)
    end
  end

  describe "unlock?" do
    it("permits psp_admin")      { expect(described_class.new(psp_admin, same_merchant_user)).to permit_action(:unlock) }
    it("denies merchant_admin")  { expect(described_class.new(merchant_admin, same_merchant_user)).to forbid_action(:unlock) }
    it("denies psp_support")     { expect(described_class.new(psp_support, same_merchant_user)).to forbid_action(:unlock) }
  end

  describe "update_role?" do
    it("permits psp_admin")      { expect(described_class.new(psp_admin, same_merchant_user)).to permit_action(:update_role) }
    it("denies merchant_admin")  { expect(described_class.new(merchant_admin, same_merchant_user)).to forbid_action(:update_role) }
  end

  describe "Scope" do
    before do
      create(:user, :merchant_admin, merchant_id: "m1")
      create(:user, :merchant_viewer, merchant_id: "m1")
      create(:user, :merchant_admin, merchant_id: "m2")
    end

    it "psp_admin sees all users" do
      scope = UserPolicy::Scope.new(psp_admin, User).resolve
      expect(scope.count).to eq(User.count)
    end

    it "merchant_admin sees only own merchant users" do
      scope = UserPolicy::Scope.new(merchant_admin, User).resolve
      expect(scope.map(&:merchant_id).uniq).to contain_exactly("m1")
    end

    it "merchant_viewer sees nothing" do
      scope = UserPolicy::Scope.new(merchant_viewer, User).resolve
      expect(scope).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run specs to verify they fail**

```bash
bundle exec rspec spec/policies/user_policy_spec.rb --format documentation
```

Expected: failures on `invite?`, `deactivate?`, `unlock?`, `update_role?`

- [ ] **Step 3: Implement the policy**

Replace the full content of `app/policies/user_policy.rb`:

```ruby
# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  def index?       = psp_admin? || merchant_admin?
  def invite?      = psp_admin? || merchant_admin?
  def deactivate?  = (psp_admin? || (merchant_admin? && own_merchant?)) && record != user
  def unlock?      = psp_admin?
  def update_role? = psp_admin?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user.psp_admin?
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

- [ ] **Step 4: Run specs to verify they pass**

```bash
bundle exec rspec spec/policies/user_policy_spec.rb --format documentation
```

Expected: all examples pass

- [ ] **Step 5: Commit**

```bash
git add app/policies/user_policy.rb spec/policies/user_policy_spec.rb
git commit -m "feat(MH-27): expand UserPolicy with invite, deactivate, unlock, update_role"
```

---

## Task 3: Services — Users::Invite and Users::Deactivate

**Files:**
- Create: `app/services/users/invite.rb`
- Create: `app/services/users/deactivate.rb`
- Create: `spec/services/users/invite_spec.rb`
- Create: `spec/services/users/deactivate_spec.rb`

**Context:** Follow the existing service pattern from `app/services/merchants/update_profile.rb` — `self.call` class method, constructor takes args, `call` does the work, returns the record. Callers check `result.errors.none?`.

`Users::Invite` creates a User with a random password (the invited user never knows it), then calls `user.send_reset_password_instructions` which generates a Devise reset token and dispatches the email. We stub `send_reset_password_instructions` in specs to avoid actual email delivery — use `allow(user).to receive(:send_reset_password_instructions)`.

- [ ] **Step 1: Write failing invite specs**

Create `spec/services/users/invite_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Users::Invite do
  def call(overrides = {})
    described_class.call({
      email:       "newuser@example.com",
      role:        "merchant_viewer",
      merchant_id: "merch_abc"
    }.merge(overrides))
  end

  describe ".call" do
    it "creates a user with the given email, role, and merchant_id" do
      expect { call }.to change(User, :count).by(1)

      user = User.last
      expect(user.email).to eq("newuser@example.com")
      expect(user.role).to eq("merchant_viewer")
      expect(user.merchant_id).to eq("merch_abc")
    end

    it "sends reset password instructions after save" do
      user_double = instance_double(User, save: true, errors: ActiveModel::Errors.new(User.new))
      allow(User).to receive(:new).and_return(user_double)
      expect(user_double).to receive(:send_reset_password_instructions)
      described_class.call(email: "x@x.com", role: "merchant_viewer", merchant_id: "merch_abc")
    end

    it "does not send email when save fails (duplicate email)" do
      create(:user, email: "newuser@example.com")
      result = call
      expect(result.errors).not_to be_empty
    end

    it "returns user with errors when role is not permitted" do
      result = call(role: "superadmin")
      expect(result.errors[:role]).to include("is not permitted")
    end

    it "creates a psp_admin user when no merchant_id given" do
      result = call(role: "psp_admin", merchant_id: nil)
      expect(result.errors).to be_empty
      expect(User.last.role).to eq("psp_admin")
    end

    it "ignores unpermitted keys in params" do
      expect {
        described_class.call(email: "safe@example.com", role: "merchant_viewer",
                             merchant_id: "m1", admin: true)
      }.to change(User, :count).by(1)
    end
  end
end
```

- [ ] **Step 2: Write failing deactivate specs**

Create `spec/services/users/deactivate_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Users::Deactivate do
  let(:actor)  { create(:user, :merchant_admin, merchant_id: "merch_abc") }
  let(:target) { create(:user, :merchant_viewer, merchant_id: "merch_abc") }

  def call(user = target, acting_as = actor)
    described_class.call(user, acting_as)
  end

  describe ".call" do
    it "sets deactivated_at on the target user" do
      freeze_time do
        call
        expect(target.reload.deactivated_at).to eq(Time.current)
      end
    end

    it "locks the target user via Devise (sets locked_at)" do
      call
      expect(target.reload.locked_at).not_to be_nil
    end

    it "returns the user" do
      result = call
      expect(result).to eq(target)
    end

    it "returns user with error when actor tries to deactivate themselves" do
      result = call(actor, actor)
      expect(result.errors[:base]).to include("You cannot deactivate your own account")
    end

    it "does not set deactivated_at when self-deactivation attempted" do
      call(actor, actor)
      expect(actor.reload.deactivated_at).to be_nil
    end
  end
end
```

- [ ] **Step 3: Run specs to verify they fail**

```bash
bundle exec rspec spec/services/users/ --format documentation
```

Expected: `NameError: uninitialized constant Users::Invite` and similar

- [ ] **Step 4: Implement Users::Invite**

Create `app/services/users/invite.rb`:

```ruby
# frozen_string_literal: true

module Users
  class Invite
    PERMITTED_ROLES = %w[psp_admin psp_support merchant_admin merchant_viewer].freeze
    private_constant :PERMITTED_ROLES

    def self.call(params) = new(params).call

    def initialize(params)
      @email       = params[:email].to_s.strip
      @role        = params[:role].to_s
      @merchant_id = params[:merchant_id]
    end

    def call
      return invalid_role_user unless PERMITTED_ROLES.include?(@role)

      user = User.new(
        email:       @email,
        role:        @role,
        merchant_id: @merchant_id,
        password:    SecureRandom.hex(24)
      )

      user.send_reset_password_instructions if user.save

      user
    end

    private

    def invalid_role_user
      user = User.new
      user.errors.add(:role, "is not permitted")
      user
    end
  end
end
```

- [ ] **Step 5: Implement Users::Deactivate**

Create `app/services/users/deactivate.rb`:

```ruby
# frozen_string_literal: true

module Users
  class Deactivate
    def self.call(user, actor) = new(user, actor).call

    def initialize(user, actor)
      @user  = user
      @actor = actor
    end

    def call
      if @user == @actor
        @user.errors.add(:base, "You cannot deactivate your own account")
        return @user
      end

      @user.update!(deactivated_at: Time.current)
      @user.lock_access!(send_instructions: false)
      @user
    end
  end
end
```

- [ ] **Step 6: Run specs to verify they pass**

```bash
bundle exec rspec spec/services/users/ --format documentation
```

Expected: all examples pass

- [ ] **Step 7: Commit**

```bash
git add app/services/users/ spec/services/users/
git commit -m "feat(MH-27): add Users::Invite and Users::Deactivate service objects"
```

---

## Task 4: letter_opener_web gem + routes + navigation

**Files:**
- Modify: `Gemfile`
- Modify: `config/routes.rb`
- Modify: `config/environments/development.rb`
- Modify: `app/views/layouts/_navigation.html.erb` (or wherever the nav partial lives)

**Context:** `letter_opener_web` intercepts ActionMailer in development and stores emails for browser preview at `/letter_opener`. We also add the new `/team` and `/admin/users` routes, and wire the Team nav link for merchant_admin users.

- [ ] **Step 1: Add letter_opener_web to Gemfile**

In `Gemfile`, inside `group :development do`:

```ruby
gem "letter_opener_web"
```

- [ ] **Step 2: Bundle install**

```bash
bundle install
```

- [ ] **Step 3: Configure ActionMailer to use letter_opener in development**

In `config/environments/development.rb`, add:

```ruby
config.action_mailer.delivery_method = :letter_opener_web
config.action_mailer.perform_deliveries = true
config.action_mailer.default_url_options = { host: "localhost", port: 3000 }
```

- [ ] **Step 4: Update routes**

Replace the full content of `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  devise_for :users

  get "up" => "rails/health#show", as: :rails_health_check
  get "health" => "rails/health#show"

  authenticated :user do
    root to: "payments#index", as: :authenticated_root
  end
  root to: redirect("/users/sign_in")

  resources :merchants, only: %i[new create index show edit update]
  resources :shops, only: %i[index show new create edit update] do
    post :credential, to: "shop_credentials#create"
    delete "credentials/:id", to: "shop_credentials#destroy", as: :credential_revoke
    get "credentials/show_once", to: "shop_credentials#show_once", as: :credential_show_once
  end

  resources :payments, only: %i[index show] do
    resource :timeline, only: :show, controller: "payment_timelines"
    member do
      post :refund
      post :void
    end
  end

  resources :team, only: %i[index new create destroy]

  namespace :admin do
    resources :users, only: %i[index new create] do
      member do
        patch :unlock
        patch :update_role
      end
    end
  end

  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?
end
```

- [ ] **Step 5: Add Team link to navigation**

Find the navigation partial (likely `app/views/layouts/application.html.erb` or a partial it renders — look for the existing `Shops` and `Payments` links). Add a Team link visible only to merchant roles, and a Users link visible only to psp_admin:

```erb
<% if current_user.merchant_role? %>
  <%= link_to t("layouts.navigation.team"), team_index_path,
        class: "..." %>
<% end %>
<% if current_user.psp_admin? %>
  <%= link_to t("layouts.navigation.users"), admin_users_path,
        class: "..." %>
<% end %>
```

Match the exact CSS classes used by existing nav links (e.g. `Shops`, `Payments`). Add i18n keys to `config/locales/en.yml`:

```yaml
layouts:
  navigation:
    team: "Team"
    users: "Users"
```

- [ ] **Step 6: Verify zeitwerk is happy**

```bash
bundle exec rails zeitwerk:check
```

Expected: `All is good!`

- [ ] **Step 7: Commit**

```bash
git add Gemfile Gemfile.lock config/routes.rb config/environments/development.rb config/locales/en.yml app/views/
git commit -m "feat(MH-27): add routes, letter_opener_web, and nav links for team and admin users"
```

---

## Task 5: TeamController + views (MH-35 + MH-36)

**Files:**
- Create: `app/controllers/team_controller.rb`
- Create: `app/views/team/index.html.erb`
- Create: `app/views/team/new.html.erb`
- Create: `spec/requests/team_spec.rb`

**Context:** `TeamController` uses `decent_exposure` (already in the Gemfile). The `expose(:team_members)` block calls `policy_scope` which returns users scoped to the current merchant. The `index` and `new` views follow the same TailAdmin table/card-form pattern as `merchants/index` and `merchants/edit`.

Status badge logic — three states based on two columns:
- `deactivated_at` present → **Deactivated** (red)
- `locked_at` present, `deactivated_at` nil → **Locked** (amber)
- Both nil → **Active** (green)

- [ ] **Step 1: Write failing request specs**

Create `spec/requests/team_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Team", type: :request do
  let_it_be(:merchant_admin)  { create(:user, :merchant_admin, merchant_id: "merch_abc") }
  let_it_be(:merchant_viewer) { create(:user, :merchant_viewer, merchant_id: "merch_abc") }
  let_it_be(:psp_admin)       { create(:user, :psp_admin) }
  let_it_be(:other_admin)     { create(:user, :merchant_admin, merchant_id: "merch_xyz") }
  let_it_be(:team_member)     { create(:user, :merchant_viewer, merchant_id: "merch_abc") }

  describe "GET /team" do
    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 200 and lists team members" do
        get team_index_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(team_member.email)
      end

      it "does not list users from other merchants" do
        get team_index_path
        expect(response.body).not_to include(other_admin.email)
      end
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "returns 403" do
        get team_index_path
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when unauthenticated" do
      it "redirects to sign in" do
        get team_index_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "GET /team/new" do
    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 200" do
        get new_team_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "returns 403" do
        get new_team_path
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /team" do
    before { sign_in merchant_admin }

    context "with valid params" do
      it "creates a user and redirects to team index" do
        expect {
          post team_index_path, params: { user: { email: "new@merch.com", role: "merchant_viewer" } }
        }.to change(User, :count).by(1)

        expect(response).to redirect_to(team_index_path)
        expect(User.last.merchant_id).to eq("merch_abc")
      end
    end

    context "with invalid email" do
      it "re-renders new with 422" do
        post team_index_path, params: { user: { email: "not-an-email", role: "merchant_viewer" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "attempting to invite a psp role" do
      it "returns an error" do
        post team_index_path, params: { user: { email: "hack@example.com", role: "psp_admin" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "returns 403" do
        post team_index_path, params: { user: { email: "x@x.com", role: "merchant_viewer" } }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "DELETE /team/:id" do
    before { sign_in merchant_admin }

    it "deactivates the team member and redirects" do
      delete team_path(team_member)
      expect(response).to redirect_to(team_index_path)
      expect(team_member.reload.deactivated_at).not_to be_nil
    end

    it "returns 403 when trying to deactivate self" do
      delete team_path(merchant_admin)
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 404 when trying to deactivate a user from another merchant" do
      delete team_path(other_admin)
      expect(response).to have_http_status(:not_found)
    end

    context "when signed in as merchant_viewer" do
      before { sign_in merchant_viewer }

      it "returns 403" do
        delete team_path(team_member)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
```

- [ ] **Step 2: Run specs to verify they fail**

```bash
bundle exec rspec spec/requests/team_spec.rb --format documentation
```

Expected: routing errors / `uninitialized constant TeamController`

- [ ] **Step 3: Implement TeamController**

Create `app/controllers/team_controller.rb`:

```ruby
# frozen_string_literal: true

class TeamController < ApplicationController
  expose(:team_members) {
    policy_scope(User, policy_scope_class: UserPolicy::Scope).order(:email)
  }

  def index
    authorize User, :index?, policy_class: UserPolicy
  end

  def new
    authorize User, :invite?, policy_class: UserPolicy
  end

  def create
    authorize User, :invite?, policy_class: UserPolicy
    result = Users::Invite.call(invite_params.merge(merchant_id: current_user.merchant_id))
    if result.errors.none?
      redirect_to team_index_path, notice: t("flash.team.invite_success", email: result.email)
    else
      flash.now[:alert] = result.errors.full_messages.to_sentence
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    member = policy_scope(User, policy_scope_class: UserPolicy::Scope).find(params[:id])
    authorize member, :deactivate?, policy_class: UserPolicy
    result = Users::Deactivate.call(member, current_user)
    if result.errors.none?
      redirect_to team_index_path, notice: t("flash.team.deactivate_success", email: member.email)
    else
      redirect_to team_index_path, alert: result.errors.full_messages.to_sentence
    end
  end

  private

  def invite_params
    params.fetch(:user, {}).permit(:email, :role)
  end
end
```

Note: `destroy` uses `policy_scope(...).find` so looking up a user from another merchant raises `ActiveRecord::RecordNotFound` (404) rather than 403 — users outside the scope simply don't exist from this controller's perspective.

- [ ] **Step 4: Implement team/index view**

Create `app/views/team/index.html.erb`:

```erb
<% content_for :title, t('.page_title') %>

<div class="mb-6 flex items-center justify-between">
  <div>
    <h1 class="text-xl font-semibold text-gray-900"><%= t('.title') %></h1>
    <p class="mt-1 text-theme-sm text-gray-500"><%= t('.subtitle') %></p>
  </div>
  <%= link_to t('.invite'), new_team_path,
        class: "btn-primary text-sm" %>
</div>

<div class="card">
  <table class="w-full text-left text-theme-sm">
    <thead>
      <tr class="border-b border-gray-200">
        <th class="py-2 pr-4 font-medium text-gray-500 border-r border-gray-100"><%= t('.table.email') %></th>
        <th class="px-4 py-2 font-medium text-gray-500 border-r border-gray-100"><%= t('.table.role') %></th>
        <th class="px-4 py-2 font-medium text-gray-500 border-r border-gray-100"><%= t('.table.status') %></th>
        <th class="px-4 py-2 font-medium text-gray-500 border-r border-gray-100"><%= t('.table.last_sign_in') %></th>
        <th class="px-4 py-2 font-medium text-gray-500"><%= t('.table.actions') %></th>
      </tr>
    </thead>
    <tbody class="divide-y divide-gray-100">
      <% if team_members.empty? %>
        <tr>
          <td colspan="5" class="py-6 text-center text-gray-500"><%= t('.table.empty') %></td>
        </tr>
      <% else %>
        <% team_members.each do |member| %>
          <tr class="hover:bg-gray-50">
            <td class="py-3 pr-4 text-gray-900 border-r border-gray-100"><%= member.email %></td>
            <td class="px-4 py-3 text-gray-600 border-r border-gray-100"><%= member.role.humanize %></td>
            <td class="px-4 py-3 border-r border-gray-100">
              <% if member.deactivated? %>
                <span class="inline-flex items-center rounded-full bg-red-100 px-2 py-0.5 text-xs font-medium text-red-700">
                  <%= t('.status.deactivated') %>
                </span>
              <% elsif member.access_locked? %>
                <span class="inline-flex items-center rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-700">
                  <%= t('.status.locked') %>
                </span>
              <% else %>
                <span class="inline-flex items-center rounded-full bg-green-100 px-2 py-0.5 text-xs font-medium text-green-700">
                  <%= t('.status.active') %>
                </span>
              <% end %>
            </td>
            <td class="px-4 py-3 text-gray-500 border-r border-gray-100">
              <%= member.last_sign_in_at&.strftime("%d %b %Y") || t('.table.never') %>
            </td>
            <td class="px-4 py-3">
              <% if member != current_user && !member.deactivated? %>
                <%= button_to t('.deactivate'), team_path(member),
                      method: :delete,
                      data: { turbo_confirm: t('.deactivate_confirm', email: member.email) },
                      class: "text-sm text-red-600 hover:text-red-800 font-medium" %>
              <% end %>
            </td>
          </tr>
        <% end %>
      <% end %>
    </tbody>
  </table>
</div>
```

- [ ] **Step 5: Implement team/new view**

Create `app/views/team/new.html.erb`:

```erb
<% content_for :title, t('.page_title') %>

<div class="mb-6">
  <h1 class="text-xl font-semibold text-gray-900"><%= t('.title') %></h1>
  <p class="mt-1 text-theme-sm text-gray-500"><%= t('.subtitle') %></p>
</div>

<div class="card max-w-lg">
  <%= form_with url: team_index_path, method: :post do %>
    <div class="space-y-4">
      <div>
        <%= label_tag "user[email]", t('.fields.email'), class: "form-label" %>
        <%= email_field_tag "user[email]", params.dig(:user, :email),
              class: "form-input mt-1", required: true, autofocus: true %>
      </div>

      <div>
        <%= label_tag "user[role]", t('.fields.role'), class: "form-label" %>
        <%= select_tag "user[role]",
              options_for_select([
                [t('.roles.merchant_admin'),  "merchant_admin"],
                [t('.roles.merchant_viewer'), "merchant_viewer"]
              ], params.dig(:user, :role)),
              class: "form-input mt-1" %>
      </div>
    </div>

    <div class="mt-6 flex items-center gap-3">
      <%= submit_tag t('.submit'), class: "btn-primary" %>
      <%= link_to t('.cancel'), team_index_path, class: "btn-secondary" %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 6: Add i18n keys**

In `config/locales/en.yml`, add at the top level under `en:`:

```yaml
flash:
  team:
    invite_success: "Invitation sent to %{email}."
    deactivate_success: "%{email} has been deactivated."

team:
  index:
    page_title: "Team"
    title: "Team"
    subtitle: "Manage your merchant portal users."
    invite: "Invite user"
    table:
      email: "Email"
      role: "Role"
      status: "Status"
      last_sign_in: "Last sign-in"
      actions: "Actions"
      never: "Never"
      empty: "No team members yet."
    status:
      active: "Active"
      locked: "Locked"
      deactivated: "Deactivated"
    deactivate: "Deactivate"
    deactivate_confirm: "Deactivate %{email}? They will lose access immediately."
  new:
    page_title: "Invite user"
    title: "Invite a team member"
    subtitle: "They will receive an email to set their password."
    fields:
      email: "Email address"
      role: "Role"
    roles:
      merchant_admin: "Admin"
      merchant_viewer: "Viewer"
    submit: "Send invite"
    cancel: "Cancel"
```

- [ ] **Step 7: Run specs to verify they pass**

```bash
bundle exec rspec spec/requests/team_spec.rb --format documentation
```

Expected: all examples pass

- [ ] **Step 8: Commit**

```bash
git add app/controllers/team_controller.rb app/views/team/ spec/requests/team_spec.rb config/locales/en.yml
git commit -m "feat(MH-35/MH-36): TeamController — invite and deactivate merchant team members"
```

---

## Task 6: Admin::UsersController + views (MH-37)

**Files:**
- Create: `app/controllers/admin/users_controller.rb`
- Create: `app/views/admin/users/index.html.erb`
- Create: `app/views/admin/users/new.html.erb`
- Create: `spec/requests/admin/users_spec.rb`

**Context:** The `admin` namespace is new — Rails will look for controllers in `app/controllers/admin/`. The `update_role` action uses a `role_params` private method (not raw `params[:user][:role]`) to keep strong parameters consistent with the rest of the codebase. The index uses Turbo Frame search (role + merchant filters) matching the pattern from `merchants/index.html.erb`.

- [ ] **Step 1: Write failing request specs**

Create `spec/requests/admin/users_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Users", type: :request do
  let_it_be(:psp_admin)      { create(:user, :psp_admin) }
  let_it_be(:psp_support)    { create(:user, :psp_support) }
  let_it_be(:merchant_admin) { create(:user, :merchant_admin, merchant_id: "merch_abc") }
  let_it_be(:merchant_user)  { create(:user, :merchant_viewer, merchant_id: "merch_abc") }
  let_it_be(:locked_user) do
    create(:user, :merchant_viewer, merchant_id: "merch_abc").tap do |u|
      u.lock_access!(send_instructions: false)
      u.update!(deactivated_at: Time.current)
    end
  end

  describe "GET /admin/users" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "returns 200 and lists all users" do
        get admin_users_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(merchant_user.email)
      end

      it "filters by role" do
        get admin_users_path, params: { role: "psp_admin" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(psp_admin.email)
        expect(response.body).not_to include(merchant_user.email)
      end

      it "filters by merchant_id" do
        get admin_users_path, params: { merchant_id: "merch_abc" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(merchant_user.email)
        expect(response.body).not_to include(psp_admin.email)
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 403" do
        get admin_users_path
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when unauthenticated" do
      it "redirects to sign in" do
        get admin_users_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "GET /admin/users/new" do
    before { sign_in psp_admin }

    it "returns 200" do
      get new_admin_user_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /admin/users" do
    before { sign_in psp_admin }

    context "with valid psp_admin params" do
      it "creates a PSP user and redirects" do
        expect {
          post admin_users_path, params: { user: { email: "new-psp@tessera.test", role: "psp_support" } }
        }.to change(User, :count).by(1)

        expect(response).to redirect_to(admin_users_path)
        expect(User.last.role).to eq("psp_support")
        expect(User.last.merchant_id).to be_nil
      end
    end

    context "with invalid email" do
      it "re-renders new with 422" do
        post admin_users_path, params: { user: { email: "bad", role: "psp_support" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 403" do
        post admin_users_path, params: { user: { email: "x@x.com", role: "psp_admin" } }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "PATCH /admin/users/:id/unlock" do
    before { sign_in psp_admin }

    it "clears locked_at and deactivated_at and redirects" do
      patch unlock_admin_user_path(locked_user)
      expect(response).to redirect_to(admin_users_path)
      locked_user.reload
      expect(locked_user.locked_at).to be_nil
      expect(locked_user.deactivated_at).to be_nil
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 403" do
        patch unlock_admin_user_path(locked_user)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "PATCH /admin/users/:id/update_role" do
    before { sign_in psp_admin }

    it "updates the role and redirects" do
      patch update_role_admin_user_path(merchant_user), params: { user: { role: "merchant_admin" } }
      expect(response).to redirect_to(admin_users_path)
      expect(merchant_user.reload.role).to eq("merchant_admin")
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 403" do
        patch update_role_admin_user_path(merchant_user), params: { user: { role: "merchant_admin" } }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
```

- [ ] **Step 2: Run specs to verify they fail**

```bash
bundle exec rspec spec/requests/admin/users_spec.rb --format documentation
```

Expected: routing errors / `uninitialized constant Admin::UsersController`

- [ ] **Step 3: Create admin directory and implement controller**

```bash
mkdir -p app/controllers/admin
```

Create `app/controllers/admin/users_controller.rb`:

```ruby
# frozen_string_literal: true

class Admin::UsersController < ApplicationController
  expose(:users) {
    scope = policy_scope(User, policy_scope_class: UserPolicy::Scope)
    scope = scope.where(role: params[:role]) if params[:role].present?
    scope = scope.where(merchant_id: params[:merchant_id]) if params[:merchant_id].present?
    scope.order(:email)
  }

  def index
    authorize User, :index?, policy_class: UserPolicy
    @pagy, @users = pagy(:offset, users)
  end

  def new
    authorize User, :invite?, policy_class: UserPolicy
  end

  def create
    authorize User, :invite?, policy_class: UserPolicy
    result = Users::Invite.call(invite_params)
    if result.errors.none?
      redirect_to admin_users_path, notice: t("flash.admin.users.invite_success", email: result.email)
    else
      flash.now[:alert] = result.errors.full_messages.to_sentence
      render :new, status: :unprocessable_content
    end
  end

  def unlock
    member = User.find(params[:id])
    authorize member, :unlock?, policy_class: UserPolicy
    member.unlock_access!
    member.update!(deactivated_at: nil)
    redirect_to admin_users_path, notice: t("flash.admin.users.unlock_success", email: member.email)
  end

  def update_role
    member = User.find(params[:id])
    authorize member, :update_role?, policy_class: UserPolicy
    if member.update(role_params[:role])
      redirect_to admin_users_path, notice: t("flash.admin.users.role_updated", email: member.email)
    else
      redirect_to admin_users_path, alert: member.errors.full_messages.to_sentence
    end
  end

  private

  def invite_params
    params.fetch(:user, {}).permit(:email, :role)
  end

  def role_params
    params.fetch(:user, {}).permit(:role)
  end
end
```

- [ ] **Step 4: Implement admin/users/index view**

Create `app/views/admin/users/index.html.erb`:

```erb
<% content_for :title, t('.page_title') %>

<div class="mb-6 flex items-center justify-between">
  <div>
    <h1 class="text-xl font-semibold text-gray-900"><%= t('.title') %></h1>
    <p class="mt-1 text-theme-sm text-gray-500"><%= t('.subtitle') %></p>
  </div>
  <%= link_to t('.invite'), new_admin_user_path, class: "btn-primary text-sm" %>
</div>

<div class="card">
  <%# Filters %>
  <%= form_with url: admin_users_path, method: :get,
        data: { controller: "filter", turbo_frame: "users-table" },
        class: "mb-4 flex gap-3" do %>
    <%= select_tag :role,
          options_for_select([
            [t('.filter.role_placeholder'), ""],
            ["PSP Admin", "psp_admin"],
            ["PSP Support", "psp_support"],
            ["Merchant Admin", "merchant_admin"],
            ["Merchant Viewer", "merchant_viewer"]
          ], params[:role]),
          class: "form-input max-w-xs",
          data: { action: "change->filter#submit" } %>
    <input type="text" name="merchant_id" value="<%= params[:merchant_id] %>"
           placeholder="<%= t('.filter.merchant_placeholder') %>"
           class="form-input max-w-xs"
           data-action="input->filter#submitDebounced" />
  <% end %>

  <%= turbo_frame_tag "users-table" do %>
    <table class="w-full text-left text-theme-sm">
      <thead>
        <tr class="border-b border-gray-200">
          <th class="py-2 pr-4 font-medium text-gray-500 border-r border-gray-100"><%= t('.table.email') %></th>
          <th class="px-4 py-2 font-medium text-gray-500 border-r border-gray-100"><%= t('.table.merchant') %></th>
          <th class="px-4 py-2 font-medium text-gray-500 border-r border-gray-100"><%= t('.table.role') %></th>
          <th class="px-4 py-2 font-medium text-gray-500 border-r border-gray-100"><%= t('.table.status') %></th>
          <th class="px-4 py-2 font-medium text-gray-500 border-r border-gray-100"><%= t('.table.last_sign_in') %></th>
          <th class="px-4 py-2 font-medium text-gray-500"><%= t('.table.actions') %></th>
        </tr>
      </thead>
      <tbody class="divide-y divide-gray-100">
        <% if @users.empty? %>
          <tr>
            <td colspan="6" class="py-6 text-center text-gray-500"><%= t('.table.empty') %></td>
          </tr>
        <% else %>
          <% @users.each do |member| %>
            <tr class="hover:bg-gray-50">
              <td class="py-3 pr-4 text-gray-900 border-r border-gray-100"><%= member.email %></td>
              <td class="px-4 py-3 font-mono text-xs text-gray-500 border-r border-gray-100">
                <%= member.merchant_id.presence || "—" %>
              </td>
              <td class="px-4 py-3 text-gray-600 border-r border-gray-100"><%= member.role.humanize %></td>
              <td class="px-4 py-3 border-r border-gray-100">
                <% if member.deactivated? %>
                  <span class="inline-flex items-center rounded-full bg-red-100 px-2 py-0.5 text-xs font-medium text-red-700">Deactivated</span>
                <% elsif member.access_locked? %>
                  <span class="inline-flex items-center rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-700">Locked</span>
                <% else %>
                  <span class="inline-flex items-center rounded-full bg-green-100 px-2 py-0.5 text-xs font-medium text-green-700">Active</span>
                <% end %>
              </td>
              <td class="px-4 py-3 text-gray-500 border-r border-gray-100">
                <%= member.last_sign_in_at&.strftime("%d %b %Y") || t('.table.never') %>
              </td>
              <td class="px-4 py-3 flex items-center gap-3">
                <% if member.deactivated? || member.access_locked? %>
                  <%= button_to t('.unlock'), unlock_admin_user_path(member),
                        method: :patch,
                        data: { turbo_confirm: t('.unlock_confirm', email: member.email) },
                        class: "text-sm text-brand-600 hover:text-brand-700 font-medium" %>
                <% end %>
                <%= select_tag "user[role]",
                      options_for_select(User.roles.keys.map { |r| [r.humanize, r] }, member.role),
                      data: {
                        controller: "filter",
                        action: "change->filter#submit",
                        turbo_method: "patch",
                        turbo_action: update_role_admin_user_path(member)
                      },
                      class: "form-input text-xs py-1" %>
              </td>
            </tr>
          <% end %>
        <% end %>
      </tbody>
    </table>
    <%== pagy_nav(@pagy) if @pagy.pages > 1 %>
  <% end %>
</div>
```

**Note on the role change select:** The inline role select uses a Turbo-driven form submit. A simpler alternative if the Stimulus approach above is fiddly: wrap each role select in a `form_with url: update_role_admin_user_path(member), method: :patch, data: { turbo: false }` with an `onchange: "this.form.submit()"` attribute. Use whichever feels cleaner.

- [ ] **Step 5: Implement admin/users/new view**

Create `app/views/admin/users/new.html.erb`:

```erb
<% content_for :title, t('.page_title') %>

<div class="mb-6">
  <h1 class="text-xl font-semibold text-gray-900"><%= t('.title') %></h1>
  <p class="mt-1 text-theme-sm text-gray-500"><%= t('.subtitle') %></p>
</div>

<div class="card max-w-lg">
  <%= form_with url: admin_users_path, method: :post do %>
    <div class="space-y-4">
      <div>
        <%= label_tag "user[email]", t('.fields.email'), class: "form-label" %>
        <%= email_field_tag "user[email]", params.dig(:user, :email),
              class: "form-input mt-1", required: true, autofocus: true %>
      </div>

      <div>
        <%= label_tag "user[role]", t('.fields.role'), class: "form-label" %>
        <%= select_tag "user[role]",
              options_for_select([
                [t('.roles.psp_admin'),   "psp_admin"],
                [t('.roles.psp_support'), "psp_support"]
              ], params.dig(:user, :role)),
              class: "form-input mt-1" %>
      </div>
    </div>

    <div class="mt-6 flex items-center gap-3">
      <%= submit_tag t('.submit'), class: "btn-primary" %>
      <%= link_to t('.cancel'), admin_users_path, class: "btn-secondary" %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 6: Add i18n keys**

In `config/locales/en.yml`, add:

```yaml
flash:
  admin:
    users:
      invite_success: "Invitation sent to %{email}."
      unlock_success: "%{email} has been unlocked."
      role_updated: "Role updated for %{email}."

admin:
  users:
    index:
      page_title: "Users"
      title: "Users"
      subtitle: "All portal users across all merchants."
      invite: "Invite PSP user"
      filter:
        role_placeholder: "All roles"
        merchant_placeholder: "Filter by merchant ID…"
      table:
        email: "Email"
        merchant: "Merchant"
        role: "Role"
        status: "Status"
        last_sign_in: "Last sign-in"
        actions: "Actions"
        never: "Never"
        empty: "No users found."
      unlock: "Unlock"
      unlock_confirm: "Unlock access for %{email}?"
    new:
      page_title: "Invite PSP user"
      title: "Invite a PSP user"
      subtitle: "They will receive an email to set their password."
      fields:
        email: "Email address"
        role: "Role"
      roles:
        psp_admin: "PSP Admin"
        psp_support: "PSP Support"
      submit: "Send invite"
      cancel: "Cancel"
```

- [ ] **Step 7: Run specs to verify they pass**

```bash
bundle exec rspec spec/requests/admin/users_spec.rb --format documentation
```

Expected: all examples pass

- [ ] **Step 8: Commit**

```bash
git add app/controllers/admin/ app/views/admin/ spec/requests/admin/ config/locales/en.yml
git commit -m "feat(MH-37): Admin::UsersController — PSP user management with invite, unlock, role change"
```

---

## Task 7: Devise mailer view customisation

**Files:**
- Create: `app/views/devise/mailer/reset_password_instructions.html.erb`

**Context:** Devise looks for mailer views in `app/views/devise/mailer/`. Creating this file overrides the gem's default. The template has access to `@resource` (the User) and `@token` (the raw reset token). We use `sign_in_count == 0` to detect a first-time invite vs a password reset request.

- [ ] **Step 1: Create the custom mailer view**

Create `app/views/devise/mailer/reset_password_instructions.html.erb`:

```erb
<% if @resource.sign_in_count == 0 %>
  <p>Hi,</p>
  <p>You've been invited to <strong>MerchantHub</strong>.</p>
  <p>Click the link below to set your password and get started. The link expires in <%= Devise.reset_password_within / 3600 %> hours.</p>
<% else %>
  <p>Hi,</p>
  <p>Someone requested a password reset for your <strong>MerchantHub</strong> account (<%= @resource.email %>).</p>
  <p>Click the link below to choose a new password. The link expires in <%= Devise.reset_password_within / 3600 %> hours.</p>
<% end %>

<p>
  <%= link_to(@resource.sign_in_count == 0 ? "Set my password" : "Reset my password",
        edit_password_url(@resource, reset_password_token: @token)) %>
</p>

<p>If you didn't request this, please ignore this email. Your account will remain unchanged.</p>
```

- [ ] **Step 2: Verify in development**

Start the Rails server and trigger an invite:
```bash
bin/rails server
```

Then sign in as a merchant_admin, go to `/team/new`, and invite a new email address. Visit `http://localhost:3000/letter_opener` — you should see the invite email with "Set my password" link.

- [ ] **Step 3: Commit**

```bash
git add app/views/devise/mailer/
git commit -m "feat(MH-27): customise Devise mailer view for invite vs password-reset copy"
```

---

## Task 8: Full suite verification and PR

- [ ] **Step 1: Run i18n-tasks to check for missing/unused keys**

```bash
bundle exec i18n-tasks health
```

Fix any reported issues before proceeding.

- [ ] **Step 2: Run the full test suite**

```bash
bundle exec rspec
```

Expected: all examples pass, 0 failures

- [ ] **Step 3: Run RuboCop**

```bash
bundle exec rubocop
```

Fix any offenses.

- [ ] **Step 4: Run Brakeman**

```bash
bundle exec brakeman --no-pager
```

Expected: 0 warnings

- [ ] **Step 5: Push branch and open PR**

```bash
git push -u origin feature/mh-27-user-management
gh pr create \
  --title "feat(MH-27): User management — invite, deactivate, unlock (MH-35, MH-36, MH-37)" \
  --body "## Summary
- MH-35: merchant_admin can invite merchant_admin/merchant_viewer users via \`/team/new\`
- MH-36: merchant_admin can view and deactivate their team at \`/team\`
- MH-37: psp_admin can browse all users, invite PSP users, unlock accounts, and change roles at \`/admin/users\`
- New \`deactivated_at\` column distinguishes admin deactivation from Devise auto-lockout
- Invite emails reuse Devise reset-password token with custom mailer view
- letter_opener_web added for email preview in development

## Test plan
- [ ] Invite a merchant user — check email arrives in /letter_opener with 'Set my password' copy
- [ ] Follow the link — confirm password can be set and user can sign in
- [ ] Deactivate a user — confirm they cannot sign in and see the deactivated message
- [ ] PSP admin unlocks a deactivated user — confirm they can sign in again
- [ ] PSP admin changes a user's role — confirm role updates
- [ ] All 291+ specs pass"
```
