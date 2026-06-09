# MH-27: User Management Design

**Stories covered:** MH-35 (merchant_admin invites staff), MH-36 (merchant_admin lists & deactivates team), MH-37 (PSP admin manages all portal users)

**Goal:** Give merchant admins the ability to invite and deactivate their own team, and give PSP admins a cross-merchant user directory with invite, role-change, and unlock capabilities.

**Architecture:** Two separate controllers (`TeamController` at `/team`, `Admin::UsersController` at `/admin/users`) with shared service objects. Devise handles token generation for invites; a custom `deactivated_at` column distinguishes admin deactivation from Devise's automatic lockout.

**Tech Stack:** Rails 8, Devise (lockable + recoverable), Pundit, Pagy, decent_exposure, letter_opener_web (development), RSpec request specs.

---

## Data model changes

### `users` table

One new column:

| Column | Type | Notes |
|---|---|---|
| `deactivated_at` | datetime | Nullable. Set by admin deactivation; nil = not deactivated. |

No other schema changes. `reset_password_token`, `locked_at`, and `unlock_token` already exist from Devise.

### `User` model additions

```ruby
scope :active,      -> { where(deactivated_at: nil) }
scope :deactivated, -> { where.not(deactivated_at: nil) }

def deactivated?
  deactivated_at.present?
end

# Devise hook — prevents sign-in for deactivated accounts
def active_for_authentication?
  super && !deactivated?
end

def inactive_message
  deactivated? ? :deactivated : super
end
```

Add to `config/locales/en.yml`:
```yaml
devise:
  failure:
    deactivated: "Your account has been deactivated. Please contact your administrator."
```

**Status logic (three distinct states):**
- **Active** — `deactivated_at` nil, `locked_at` nil
- **Locked** — `locked_at` present, `deactivated_at` nil (Devise auto-lock after failed attempts)
- **Deactivated** — `deactivated_at` present (admin action; `locked_at` also set as belt-and-braces)

---

## Gem additions

```ruby
# Gemfile
group :development do
  gem "letter_opener_web"
end
```

Route the preview UI:
```ruby
# config/routes.rb (development only)
mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?
```

---

## MH-35 + MH-36: Merchant team management

### Routes

```ruby
resources :team, only: %i[index new create destroy]
```

### Controller — `app/controllers/team_controller.rb`

```ruby
class TeamController < ApplicationController
  expose(:team_members) {
    policy_scope(User, policy_scope_class: UserPolicy::Scope)
      .order(:email)
  }
  expose(:user) { User.new }

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
    member = User.find(params[:id])
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

### Views

**`app/views/team/index.html.erb`** — TailAdmin data table:
- Columns: Email, Role badge, Status badge (Active / Locked / Deactivated), Last sign-in, Actions
- "Deactivate" button per row — hidden for `current_user` (cannot deactivate self)
- "Invite user" button top-right linking to `new_team_path`
- Empty state when no team members

**`app/views/team/new.html.erb`** — invite card form:
- Email field
- Role dropdown: `merchant_admin`, `merchant_viewer` only (never psp roles)
- Submit "Send invite", cancel back to `team_index_path`

---

## MH-37: PSP admin user management

### Routes

```ruby
namespace :admin do
  resources :users, only: %i[index new create] do
    member do
      patch :unlock
      patch :update_role
    end
  end
end
```

### Controller — `app/controllers/admin/users_controller.rb`

```ruby
class Admin::UsersController < ApplicationController
  expose(:users) {
    scope = policy_scope(User, policy_scope_class: UserPolicy::Scope)
    scope = scope.where(role: params[:role]) if params[:role].present?
    scope = scope.where(merchant_id: params[:merchant_id]) if params[:merchant_id].present?
    scope.order(:email)
  }
  expose(:user) { User.new }

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
    if member.update(role: params[:user][:role])
      redirect_to admin_users_path, notice: t("flash.admin.users.role_updated", email: member.email)
    else
      redirect_to admin_users_path, alert: member.errors.full_messages.to_sentence
    end
  end

  private

  def invite_params
    params.fetch(:user, {}).permit(:email, :role)
  end
end
```

### Views

**`app/views/admin/users/index.html.erb`** — TailAdmin data table:
- Columns: Email, Merchant, Role badge, Status badge, Last sign-in, Actions
- Filter bar: role select, merchant_id search (Turbo Frame, FilterController)
- "Unlock" button shown only for locked/deactivated rows
- "Change role" inline select or link to modal
- "Invite PSP user" button top-right
- Paginated via Pagy

**`app/views/admin/users/new.html.erb`** — invite card form:
- Email field
- Role dropdown: `psp_admin`, `psp_support` only (never merchant roles)
- Submit "Send invite", cancel back to `admin_users_path`

---

## Services

### `app/services/users/invite.rb`

```ruby
module Users
  class Invite
    PERMITTED_ROLES = %w[psp_admin psp_support merchant_admin merchant_viewer].freeze

    def self.call(params) = new(params).call

    def initialize(params)
      @email      = params[:email].to_s.strip
      @role       = params[:role].to_s
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

      if user.save
        user.send_reset_password_instructions
      end

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

Devise's `send_reset_password_instructions` generates a secure token, persists it, and dispatches `Devise::Mailer#reset_password_instructions`. We customise that view to read as an invite.

### `app/services/users/deactivate.rb`

```ruby
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

---

## Mailer customisation

Override the Devise reset password view to read as an invite when the user has never signed in (i.e., `sign_in_count == 0`):

**`app/views/devise/mailer/reset_password_instructions.html.erb`**

```erb
<% if @resource.sign_in_count == 0 %>
  <p>You've been invited to MerchantHub.</p>
  <p>Click the link below to set your password and get started:</p>
<% else %>
  <p>Someone requested a password reset for your MerchantHub account.</p>
  <p>Click the link below to reset your password:</p>
<% end %>

<p><%= link_to "Set my password", edit_password_url(@resource, reset_password_token: @token) %></p>

<p>This link expires in <%= Devise.reset_password_within / 3600 %> hours.</p>
<p>If you didn't request this, please ignore this email.</p>
```

---

## Policy — `app/policies/user_policy.rb`

```ruby
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

---

## i18n — `config/locales/en.yml` additions

```yaml
devise:
  failure:
    deactivated: "Your account has been deactivated. Please contact your administrator."

flash:
  team:
    invite_success: "Invitation sent to %{email}."
    deactivate_success: "%{email} has been deactivated."
  admin:
    users:
      invite_success: "Invitation sent to %{email}."
      unlock_success: "%{email} has been unlocked."
      role_updated: "Role updated for %{email}."

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

admin:
  users:
    index:
      page_title: "Users"
      title: "Users"
      subtitle: "All portal users across all merchants."
      invite: "Invite PSP user"
      filter:
        role_placeholder: "All roles"
        merchant_placeholder: "All merchants"
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

---

## Specs

### `spec/models/user_spec.rb` additions
- `active_for_authentication?` returns false when `deactivated_at` present
- `inactive_message` returns `:deactivated` when deactivated
- `deactivated?` scope and helper

### `spec/services/users/invite_spec.rb`
- Creates user with correct role and merchant_id
- Sends reset password instructions
- Returns user with errors on duplicate email
- Returns user with errors on invalid role

### `spec/services/users/deactivate_spec.rb`
- Sets `deactivated_at` and `locked_at`
- Returns user with error when actor == user (self-deactivation guard)

### `spec/policies/user_policy_spec.rb`
- Full coverage: index?, invite?, deactivate? (own/other/self), unlock?, update_role?
- Scope: psp_admin sees all, merchant_admin sees own merchant, others see none

### `spec/requests/team_spec.rb`
- `GET /team` — 200 for merchant_admin, 403 for merchant_viewer, 302 unauthenticated
- `GET /team/new` — 200 for merchant_admin, 403 for merchant_viewer
- `POST /team` — success redirects, invalid email 422, psp role rejected
- `DELETE /team/:id` — deactivates user, 403 for self, 403 for other merchant

### `spec/requests/admin/users_spec.rb`
- `GET /admin/users` — 200 for psp_admin, 403 for merchant_admin
- `GET /admin/users/new` — 200 for psp_admin
- `POST /admin/users` — creates psp user, merchant role rejected
- `PATCH /admin/users/:id/unlock` — unlocks user, psp_admin only
- `PATCH /admin/users/:id/update_role` — changes role, psp_admin only

---

## File summary

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
| Modify | `Gemfile` (letter_opener_web) |
| Modify | `spec/models/user_spec.rb` |
| Create | `spec/services/users/invite_spec.rb` |
| Create | `spec/services/users/deactivate_spec.rb` |
| Modify | `spec/policies/user_policy_spec.rb` |
| Create | `spec/requests/team_spec.rb` |
| Create | `spec/requests/admin/users_spec.rb` |
