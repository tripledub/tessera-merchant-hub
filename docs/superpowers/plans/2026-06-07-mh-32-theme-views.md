# MH-32: Theme Application Across All Views — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the TailAdmin theme consistently to every view — auth screens, payments, shops, onboarding, errors, credentials — with no behaviour changes.

**Architecture:** Restore two missing CSS utilities (`form-select`, `table-action`), add a shared auth card partial for Devise views, then restyle each view group in turn using existing `card`, `btn-*`, `form-input`, `form-label`, and `badge-*` utilities.

**Tech Stack:** Rails 8, ERB, Tailwind CSS v4 (CSS-first, compiled via `tailwindcss-rails`), Propshaft, Devise, Pundit

---

## File Map

| File | Action |
|---|---|
| `app/assets/tailwind/application.css` | Add `form-select` + `table-action` utilities |
| `app/views/layouts/_auth_card.html.erb` | Create — shared centred-card wrapper for all Devise views |
| `app/views/devise/sessions/new.html.erb` | Rewrite |
| `app/views/devise/passwords/new.html.erb` | Rewrite |
| `app/views/devise/passwords/edit.html.erb` | Rewrite |
| `app/views/devise/registrations/edit.html.erb` | Rewrite |
| `app/views/devise/unlocks/new.html.erb` | Rewrite |
| `app/views/devise/confirmations/new.html.erb` | Rewrite |
| `app/views/payments/_status_badge.html.erb` | Rewrite — use `badge-*` utilities |
| `app/views/payments/index.html.erb` | Restyle — page header, form-*, card, table, badges |
| `app/views/payments/show.html.erb` | Restyle — page header, card grid, back link |
| `app/views/shops/index.html.erb` | Restyle — page header + action, card, table, badges |
| `app/views/shops/show.html.erb` | Restyle — page header, card grid, back link |
| `app/views/shops/new.html.erb` | Restyle — form-label/input, btn-primary/secondary |
| `app/views/shops/edit.html.erb` | Restyle — form-label/input, btn-primary/secondary |
| `app/views/shops/_credentials.html.erb` | Restyle — table, badge-* for status |
| `app/views/merchants/new.html.erb` | Restyle — section dividers, form-label/input, btn-primary/secondary |
| `app/views/errors/forbidden.html.erb` | Restyle — centred error card |
| `app/views/shop_credentials/show_once.html.erb` | Restyle — card, code blocks, warning banner |

---

## Task 1: Restore missing CSS utilities

**Files:**
- Modify: `app/assets/tailwind/application.css`

- [ ] **Add `form-select` and `table-action` utilities** after the existing `@utility btn-danger` block:

```css
@utility form-select {
  @apply block w-full rounded-lg border border-gray-300 bg-white px-4 py-2.5 text-theme-sm text-gray-900
         focus:border-brand-500 focus:ring-2 focus:ring-brand-500/20 focus:outline-none
         dark:border-gray-700 dark:bg-gray-900 dark:text-white dark:focus:border-brand-400;
  appearance: none;
}

@utility table-action {
  @apply text-theme-sm font-medium text-brand-600 hover:text-brand-700 min-h-11 inline-flex items-center;
}
```

- [ ] **Rebuild CSS and verify**

```bash
bin/rails tailwindcss:build
grep -c "form-select\|table-action" app/assets/builds/tailwind.css
# Expected: 2
```

- [ ] **Run tests**

```bash
bundle exec rspec --format progress
# Expected: 194 examples, 0 failures
```

- [ ] **Commit**

```bash
git add app/assets/tailwind/application.css
git commit -m "style: restore form-select and table-action utilities (MH-32)"
```

---

## Task 2: Auth card partial

**Files:**
- Create: `app/views/layouts/_auth_card.html.erb`

- [ ] **Create the partial**

```erb
<%# Centred card wrapper for all unauthenticated Devise views.
    Usage: render "layouts/auth_card", title: "Sign in" do
             ...form content...
           end %>
<div class="flex min-h-screen items-center justify-center bg-gray-50 px-4 py-12">
  <div class="w-full max-w-md">

    <%# Brand mark %>
    <div class="mb-8 flex flex-col items-center gap-3">
      <div class="flex h-12 w-12 items-center justify-center rounded-xl bg-brand-500">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="white"
             class="h-7 w-7" aria-hidden="true">
          <path d="M4.5 3.75a3 3 0 0 0-3 3v.75h21v-.75a3 3 0 0 0-3-3h-15Z" />
          <path fill-rule="evenodd" d="M22.5 9.75h-21v7.5a3 3 0 0 0 3 3h15a3 3 0 0 0 3-3v-7.5Zm-18 3.75a.75.75 0 0 1 .75-.75h6a.75.75 0 0 1 0 1.5h-6a.75.75 0 0 1-.75-.75Zm.75 2.25a.75.75 0 0 0 0 1.5h3a.75.75 0 0 0 0-1.5h-3Z" clip-rule="evenodd" />
        </svg>
      </div>
      <span class="text-xl font-semibold text-gray-900">MerchantHub</span>
    </div>

    <%# Card %>
    <div class="card">
      <h1 class="mb-6 text-lg font-semibold text-gray-900"><%= title %></h1>
      <%= yield %>
    </div>

  </div>
</div>
```

- [ ] **Run tests**

```bash
bundle exec rspec --format progress
# Expected: 194 examples, 0 failures
```

---

## Task 3: Rewrite Devise views

**Files:**
- Modify: `app/views/devise/sessions/new.html.erb`
- Modify: `app/views/devise/passwords/new.html.erb`
- Modify: `app/views/devise/passwords/edit.html.erb`
- Modify: `app/views/devise/registrations/edit.html.erb`
- Modify: `app/views/devise/unlocks/new.html.erb`
- Modify: `app/views/devise/confirmations/new.html.erb`

- [ ] **Rewrite `devise/sessions/new.html.erb`**

```erb
<%= render "layouts/auth_card", title: "Sign in to your account" do %>
  <%= form_for(resource, as: resource_name, url: session_path(resource_name)) do |f| %>
    <%= render "devise/shared/error_messages", resource: resource %>

    <div class="space-y-5">
      <div>
        <%= f.label :email, "Email address", class: "form-label" %>
        <%= f.email_field :email, autofocus: true, autocomplete: "email",
              class: "form-input mt-1" %>
      </div>

      <div>
        <%= f.label :password, "Password", class: "form-label" %>
        <%= f.password_field :password, autocomplete: "current-password",
              class: "form-input mt-1" %>
      </div>

      <% if devise_mapping.rememberable? %>
        <div class="flex items-center gap-2">
          <%= f.check_box :remember_me,
                class: "h-4 w-4 rounded border-gray-300 text-brand-500 focus:ring-brand-500" %>
          <%= f.label :remember_me, "Remember me",
                class: "text-theme-sm text-gray-700 cursor-pointer" %>
        </div>
      <% end %>

      <%= f.submit "Sign in", class: "btn btn-primary w-full mt-2" %>
    </div>
  <% end %>

  <div class="mt-6 space-y-2 text-center text-theme-sm text-gray-500">
    <%= render "devise/shared/links" %>
  </div>
<% end %>
```

- [ ] **Rewrite `devise/passwords/new.html.erb`**

```erb
<%= render "layouts/auth_card", title: "Forgot your password?" do %>
  <p class="mb-5 text-theme-sm text-gray-500">
    Enter your email and we'll send you reset instructions.
  </p>

  <%= form_for(resource, as: resource_name, url: password_path(resource_name),
        html: { method: :post }) do |f| %>
    <%= render "devise/shared/error_messages", resource: resource %>

    <div class="space-y-5">
      <div>
        <%= f.label :email, "Email address", class: "form-label" %>
        <%= f.email_field :email, autofocus: true, autocomplete: "email",
              class: "form-input mt-1" %>
      </div>

      <%= f.submit "Send reset instructions", class: "btn btn-primary w-full" %>
    </div>
  <% end %>

  <div class="mt-6 text-center text-theme-sm text-gray-500">
    <%= render "devise/shared/links" %>
  </div>
<% end %>
```

- [ ] **Rewrite `devise/passwords/edit.html.erb`**

```erb
<%= render "layouts/auth_card", title: "Set new password" do %>
  <%= form_for(resource, as: resource_name, url: password_path(resource_name),
        html: { method: :put }) do |f| %>
    <%= render "devise/shared/error_messages", resource: resource %>
    <%= f.hidden_field :reset_password_token %>

    <div class="space-y-5">
      <div>
        <%= f.label :password, "New password", class: "form-label" %>
        <% if @minimum_password_length %>
          <p class="text-xs text-gray-500 mt-0.5">Minimum <%= @minimum_password_length %> characters</p>
        <% end %>
        <%= f.password_field :password, autofocus: true, autocomplete: "new-password",
              class: "form-input mt-1" %>
      </div>

      <div>
        <%= f.label :password_confirmation, "Confirm new password", class: "form-label" %>
        <%= f.password_field :password_confirmation, autocomplete: "new-password",
              class: "form-input mt-1" %>
      </div>

      <%= f.submit "Set new password", class: "btn btn-primary w-full" %>
    </div>
  <% end %>

  <div class="mt-6 text-center text-theme-sm text-gray-500">
    <%= render "devise/shared/links" %>
  </div>
<% end %>
```

- [ ] **Rewrite `devise/registrations/edit.html.erb`**

```erb
<% content_for :page_title, "Account settings" %>

<div class="max-w-md">
  <div class="mb-6">
    <h1 class="text-xl font-semibold text-gray-900">Account settings</h1>
    <p class="mt-0.5 text-theme-sm text-gray-500">Update your email or password.</p>
  </div>

  <div class="card">
    <%= form_for(resource, as: resource_name, url: registration_path(resource_name),
          html: { method: :put }) do |f| %>
      <%= render "devise/shared/error_messages", resource: resource %>

      <div class="space-y-5">
        <div>
          <%= f.label :email, "Email address", class: "form-label" %>
          <%= f.email_field :email, autofocus: true, autocomplete: "email",
                class: "form-input mt-1" %>
        </div>

        <div>
          <%= f.label :password, "New password", class: "form-label" %>
          <p class="text-xs text-gray-500 mt-0.5">Leave blank to keep current password</p>
          <%= f.password_field :password, autocomplete: "new-password",
                class: "form-input mt-1" %>
        </div>

        <div>
          <%= f.label :password_confirmation, "Confirm new password", class: "form-label" %>
          <%= f.password_field :password_confirmation, autocomplete: "new-password",
                class: "form-input mt-1" %>
        </div>

        <div class="border-t border-gray-200 pt-5">
          <%= f.label :current_password, "Current password", class: "form-label" %>
          <p class="text-xs text-gray-500 mt-0.5">Required to confirm changes</p>
          <%= f.password_field :current_password, autocomplete: "current-password",
                class: "form-input mt-1" %>
        </div>

        <div class="flex gap-3 pt-2">
          <%= f.submit "Save changes", class: "btn btn-primary" %>
          <%= link_to "Cancel", :back, class: "btn btn-secondary" %>
        </div>
      </div>
    <% end %>
  </div>
</div>
```

- [ ] **Rewrite `devise/unlocks/new.html.erb`**

```erb
<%= render "layouts/auth_card", title: "Unlock your account" do %>
  <p class="mb-5 text-theme-sm text-gray-500">
    Enter your email and we'll send you unlock instructions.
  </p>

  <%= form_for(resource, as: resource_name, url: unlock_path(resource_name),
        html: { method: :post }) do |f| %>
    <%= render "devise/shared/error_messages", resource: resource %>

    <div class="space-y-5">
      <div>
        <%= f.label :email, "Email address", class: "form-label" %>
        <%= f.email_field :email, autofocus: true, autocomplete: "email",
              class: "form-input mt-1" %>
      </div>

      <%= f.submit "Send unlock instructions", class: "btn btn-primary w-full" %>
    </div>
  <% end %>

  <div class="mt-6 text-center text-theme-sm text-gray-500">
    <%= render "devise/shared/links" %>
  </div>
<% end %>
```

- [ ] **Rewrite `devise/confirmations/new.html.erb`**

```erb
<%= render "layouts/auth_card", title: "Resend confirmation" do %>
  <p class="mb-5 text-theme-sm text-gray-500">
    Enter your email and we'll send you a new confirmation link.
  </p>

  <%= form_for(resource, as: resource_name, url: confirmation_path(resource_name),
        html: { method: :post }) do |f| %>
    <%= render "devise/shared/error_messages", resource: resource %>

    <div class="space-y-5">
      <div>
        <%= f.label :email, "Email address", class: "form-label" %>
        <%= f.email_field :email, autofocus: true, autocomplete: "email",
              class: "form-input mt-1" %>
      </div>

      <%= f.submit "Resend confirmation", class: "btn btn-primary w-full" %>
    </div>
  <% end %>

  <div class="mt-6 text-center text-theme-sm text-gray-500">
    <%= render "devise/shared/links" %>
  </div>
<% end %>
```

- [ ] **Run tests**

```bash
bundle exec rspec --format progress
# Expected: 194 examples, 0 failures
```

- [ ] **Commit**

```bash
git add app/views/layouts/_auth_card.html.erb app/views/devise/
git commit -m "style: themed auth screens with centred card layout (MH-32)"
```

---

## Task 4: Status badge

**Files:**
- Modify: `app/views/payments/_status_badge.html.erb`

- [ ] **Rewrite to use `badge-*` utilities**

```erb
<%
  css = case status
        when "succeeded" then "badge badge-success"
        when "failed"    then "badge badge-error"
        when "pending"   then "badge badge-warning"
        when "refunded"  then "badge badge-info"
        else                  "badge badge-gray"
        end
%>
<span class="<%= css %>"><%= status.capitalize %></span>
```

- [ ] **Run tests**

```bash
bundle exec rspec --format progress
# Expected: 194 examples, 0 failures
```

---

## Task 5: Payments index

**Files:**
- Modify: `app/views/payments/index.html.erb`

- [ ] **Rewrite the view**

```erb
<% content_for :title, "Payments" %>

<%# Page header %>
<div class="mb-6 flex items-center justify-between">
  <div>
    <h1 class="text-xl font-semibold text-gray-900">Payments</h1>
    <p class="mt-0.5 text-theme-sm text-gray-500">All payment transactions across your shops</p>
  </div>
</div>

<%# Filter bar %>
<%= form_with url: payments_path, method: :get,
      class: "mb-6 flex flex-col gap-3 sm:flex-row sm:items-end" do |f| %>
  <div class="sm:w-48">
    <%= f.label :status, "Status", class: "form-label" %>
    <%= f.select :status,
          [["All statuses", ""], ["Succeeded", "succeeded"], ["Failed", "failed"],
           ["Pending", "pending"], ["Refunded", "refunded"]],
          { selected: params[:status] },
          class: "form-select mt-1" %>
  </div>
  <div class="flex gap-3">
    <%= f.submit "Filter", class: "btn btn-primary" %>
    <% if params[:status].present? %>
      <%= link_to "Clear", payments_path, class: "btn btn-secondary" %>
    <% end %>
  </div>
<% end %>

<%# Table %>
<div class="card overflow-hidden p-0">
  <div class="overflow-x-auto">
    <table class="min-w-full divide-y divide-gray-200">
      <thead class="bg-gray-50">
        <tr>
          <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500">ID</th>
          <% if current_user.psp_role? %>
            <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500">Shop</th>
          <% end %>
          <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500">Amount</th>
          <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500">Status</th>
          <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500">Created</th>
          <th class="relative px-4 py-3"><span class="sr-only">View</span></th>
        </tr>
      </thead>
      <tbody class="divide-y divide-gray-200 bg-white">
        <% @payments.each do |payment| %>
          <tr class="hover:bg-gray-50">
            <td class="px-4 py-3 text-theme-sm font-mono text-gray-900 truncate max-w-[12rem]">
              <%= payment.id %>
            </td>
            <% if current_user.psp_role? %>
              <td class="px-4 py-3 text-theme-sm text-gray-500"><%= payment.shop_id %></td>
            <% end %>
            <td class="px-4 py-3 text-theme-sm text-gray-900 whitespace-nowrap">
              <%= number_to_currency(payment.amount / 100.0, unit: payment.currency + " ") %>
            </td>
            <td class="px-4 py-3">
              <%= render partial: "payments/status_badge", locals: { status: payment.status } %>
            </td>
            <td class="px-4 py-3 text-theme-sm text-gray-500 whitespace-nowrap">
              <%= payment.inserted_at&.strftime("%d %b %Y %H:%M") %>
            </td>
            <td class="px-4 py-3 text-right">
              <%= link_to "View", payment_path(payment.id), class: "table-action" %>
            </td>
          </tr>
        <% end %>
        <% if @payments.empty? %>
          <tr>
            <td colspan="<%= current_user.psp_role? ? 6 : 5 %>"
                class="px-4 py-10 text-center text-theme-sm text-gray-500">
              No payments found.
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>
</div>

<%# Pagination %>
<% if @pagy.pages > 1 %>
  <div class="mt-4 flex justify-center text-theme-sm">
    <%== @pagy.series_nav %>
  </div>
<% end %>
```

- [ ] **Run tests**

```bash
bundle exec rspec --format progress
# Expected: 194 examples, 0 failures
```

---

## Task 6: Payments show

**Files:**
- Modify: `app/views/payments/show.html.erb`

- [ ] **Read the current file first**

```bash
cat app/views/payments/show.html.erb
```

- [ ] **Rewrite the view** (replace full contents):

```erb
<% content_for :title, "Payment" %>

<div class="max-w-4xl">
  <%# Back link %>
  <div class="mb-6">
    <%= link_to "← Back to payments", payments_path,
          class: "text-theme-sm font-medium text-brand-600 hover:text-brand-700" %>
  </div>

  <%# Page header %>
  <div class="mb-6 flex items-start justify-between gap-4">
    <div>
      <h1 class="text-xl font-semibold text-gray-900">Payment</h1>
      <p class="mt-0.5 font-mono text-theme-sm text-gray-500"><%= @payment.id %></p>
    </div>
    <%= render partial: "payments/status_badge", locals: { status: @payment.status } %>
  </div>

  <%# Detail grid %>
  <dl class="grid grid-cols-1 gap-4 sm:grid-cols-2">
    <div class="card">
      <dt class="text-xs font-semibold uppercase tracking-wider text-gray-500">Amount</dt>
      <dd class="mt-1 text-lg font-semibold text-gray-900">
        <%= number_to_currency(@payment.amount / 100.0, unit: @payment.currency + " ") %>
      </dd>
    </div>

    <div class="card">
      <dt class="text-xs font-semibold uppercase tracking-wider text-gray-500">Shop</dt>
      <dd class="mt-1 text-theme-sm font-mono text-gray-900"><%= @payment.shop_id %></dd>
    </div>

    <% if @payment.merchant_reference.present? %>
      <div class="card">
        <dt class="text-xs font-semibold uppercase tracking-wider text-gray-500">Merchant Reference</dt>
        <dd class="mt-1 text-theme-sm font-mono text-gray-900"><%= @payment.merchant_reference %></dd>
      </div>
    <% end %>

    <div class="card">
      <dt class="text-xs font-semibold uppercase tracking-wider text-gray-500">Created</dt>
      <dd class="mt-1 text-theme-sm text-gray-900">
        <%= @payment.inserted_at&.strftime("%d %b %Y at %H:%M UTC") %>
      </dd>
    </div>

    <% if @payment.idempotency_key.present? %>
      <div class="card sm:col-span-2">
        <dt class="text-xs font-semibold uppercase tracking-wider text-gray-500">Idempotency Key</dt>
        <dd class="mt-1 text-theme-sm font-mono text-gray-900 break-all"><%= @payment.idempotency_key %></dd>
      </div>
    <% end %>
  </dl>

  <%# Timeline %>
  <% if @timeline.present? %>
    <div class="mt-8">
      <h2 class="mb-4 text-base font-semibold text-gray-900">Timeline</h2>
      <div class="card space-y-4">
        <% @timeline.each do |event| %>
          <div class="flex items-start gap-3">
            <div class="mt-0.5 h-2 w-2 shrink-0 rounded-full bg-brand-500"></div>
            <div>
              <p class="text-theme-sm font-medium text-gray-900"><%= event.event_type %></p>
              <p class="text-xs text-gray-500">
                <%= event.occurred_at&.strftime("%d %b %Y %H:%M UTC") %>
                <% if event.actor.present? %> · <%= event.actor %><% end %>
              </p>
            </div>
          </div>
        <% end %>
      </div>
    </div>
  <% end %>
</div>
```

- [ ] **Run tests**

```bash
bundle exec rspec --format progress
# Expected: 194 examples, 0 failures
```

- [ ] **Commit**

```bash
git add app/views/payments/
git commit -m "style: theme payments views with card layout and badge utilities (MH-32)"
```

---

## Task 7: Shops index

**Files:**
- Modify: `app/views/shops/index.html.erb`

- [ ] **Rewrite the view**

```erb
<% content_for :title, "Shops" %>

<%# Page header %>
<div class="mb-6 flex items-center justify-between">
  <div>
    <h1 class="text-xl font-semibold text-gray-900">Shops</h1>
    <p class="mt-0.5 text-theme-sm text-gray-500">Manage your payment shops and API credentials</p>
  </div>
  <% if ShopPolicy.new(current_user, Tessera::Shop).create? %>
    <%= link_to "Add shop", new_shop_path, class: "btn btn-primary" %>
  <% end %>
</div>

<%# Table %>
<div class="card overflow-hidden p-0">
  <div class="overflow-x-auto">
    <table class="min-w-full divide-y divide-gray-200">
      <thead class="bg-gray-50">
        <tr>
          <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500">Shop ID</th>
          <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500">Name</th>
          <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500">Territory</th>
          <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500">Mode</th>
          <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500">Notification URL</th>
          <th class="relative px-4 py-3"><span class="sr-only">View</span></th>
        </tr>
      </thead>
      <tbody class="divide-y divide-gray-200 bg-white">
        <% @shops.each do |shop| %>
          <tr class="hover:bg-gray-50">
            <td class="px-4 py-3 text-theme-sm font-mono text-gray-900"><%= shop.shop_id %></td>
            <td class="px-4 py-3 text-theme-sm text-gray-900"><%= shop.name %></td>
            <td class="px-4 py-3 text-theme-sm text-gray-500"><%= shop.country.presence || "—" %></td>
            <td class="px-4 py-3">
              <span class="<%= shop.test_mode? ? 'badge badge-warning' : 'badge badge-success' %>">
                <%= shop.test_mode? ? "Test" : "Live" %>
              </span>
            </td>
            <td class="px-4 py-3 text-theme-sm text-gray-500 truncate max-w-xs">
              <%= shop.notification_url.presence || "—" %>
            </td>
            <td class="px-4 py-3 text-right">
              <%= link_to "View", shop_path(shop), class: "table-action" %>
            </td>
          </tr>
        <% end %>
        <% if @shops.empty? %>
          <tr>
            <td colspan="6" class="px-4 py-10 text-center text-theme-sm text-gray-500">
              No shops found.
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>
</div>
```

- [ ] **Run tests**

```bash
bundle exec rspec --format progress
# Expected: 194 examples, 0 failures
```

---

## Task 8: Shops show

**Files:**
- Modify: `app/views/shops/show.html.erb`

- [ ] **Rewrite the view**

```erb
<% content_for :title, @shop.name %>

<div class="max-w-2xl">
  <%# Back link %>
  <div class="mb-6">
    <%= link_to "← Back to shops", shops_path,
          class: "text-theme-sm font-medium text-brand-600 hover:text-brand-700" %>
  </div>

  <%# Page header %>
  <div class="mb-6 flex items-start justify-between gap-4">
    <h1 class="text-xl font-semibold text-gray-900"><%= @shop.name %></h1>
    <% if ShopPolicy.new(current_user, @shop).update? %>
      <%= link_to "Edit configuration", edit_shop_path(@shop), class: "btn btn-secondary shrink-0" %>
    <% end %>
  </div>

  <%# Detail grid %>
  <dl class="grid grid-cols-1 gap-4 sm:grid-cols-2">
    <div class="card">
      <dt class="text-xs font-semibold uppercase tracking-wider text-gray-500">Shop ID</dt>
      <dd class="mt-1 text-theme-sm font-mono text-gray-900"><%= @shop.shop_id %></dd>
    </div>

    <div class="card">
      <dt class="text-xs font-semibold uppercase tracking-wider text-gray-500">Territory</dt>
      <dd class="mt-1 text-theme-sm text-gray-900"><%= @shop.country.presence || "—" %></dd>
    </div>

    <div class="card">
      <dt class="text-xs font-semibold uppercase tracking-wider text-gray-500">Mode</dt>
      <dd class="mt-2">
        <span class="<%= @shop.test_mode? ? 'badge badge-warning' : 'badge badge-success' %>">
          <%= @shop.test_mode? ? "Test" : "Live" %>
        </span>
      </dd>
    </div>

    <div class="card sm:col-span-2">
      <dt class="text-xs font-semibold uppercase tracking-wider text-gray-500">Notification URL</dt>
      <dd class="mt-1 text-theme-sm text-gray-900 break-all">
        <%= @shop.notification_url.presence || "Not set" %>
      </dd>
    </div>
  </dl>

  <%= render "shops/credentials", shop: @shop %>
</div>
```

- [ ] **Run tests**

```bash
bundle exec rspec --format progress
# Expected: 194 examples, 0 failures
```

---

## Task 9: Shops new and edit

**Files:**
- Modify: `app/views/shops/new.html.erb`
- Modify: `app/views/shops/edit.html.erb`

- [ ] **Rewrite `shops/new.html.erb`**

```erb
<% content_for :title, "Add shop" %>

<div class="max-w-2xl">
  <%# Back link %>
  <div class="mb-6">
    <%= link_to "← Back to shops", shops_path,
          class: "text-theme-sm font-medium text-brand-600 hover:text-brand-700" %>
  </div>

  <%# Page header %>
  <div class="mb-6">
    <h1 class="text-xl font-semibold text-gray-900">Add shop</h1>
    <p class="mt-0.5 text-theme-sm text-gray-500">
      Provisions a new shop in tessera-core under
      <%= current_user.psp_admin? ? "the selected merchant" : "your merchant" %>.
    </p>
  </div>

  <div class="card">
    <%= form_with url: shops_path, method: :post, class: "space-y-5" do |f| %>
      <% if current_user.psp_admin? %>
        <div>
          <%= label_tag "shop[merchant_id]", "Merchant ID", class: "form-label" %>
          <%= text_field_tag "shop[merchant_id]", params.dig(:shop, :merchant_id),
                class: "form-input mt-1 font-mono" %>
        </div>
      <% end %>

      <div>
        <%= label_tag "shop[name]", "Shop name", class: "form-label" %>
        <%= text_field_tag "shop[name]", params.dig(:shop, :name), class: "form-input mt-1" %>
      </div>

      <div>
        <%= label_tag "shop[country]", "Territory (ISO-2)", class: "form-label" %>
        <%= text_field_tag "shop[country]", params.dig(:shop, :country),
              maxlength: 2, class: "form-input mt-1" %>
      </div>

      <div>
        <%= label_tag "shop[notification_url]", "Notification URL", class: "form-label" %>
        <p class="text-xs text-gray-500 mt-0.5">Optional. HTTPS URL for payment webhooks.</p>
        <%= url_field_tag "shop[notification_url]", params.dig(:shop, :notification_url),
              placeholder: "https://your-server.com/webhooks",
              class: "form-input mt-1" %>
      </div>

      <div class="flex flex-col gap-3 pt-2 sm:flex-row">
        <%= f.submit "Create shop", class: "btn btn-primary w-full sm:w-auto" %>
        <%= link_to "Cancel", shops_path, class: "btn btn-secondary w-full sm:w-auto" %>
      </div>
    <% end %>
  </div>
</div>
```

- [ ] **Rewrite `shops/edit.html.erb`**

```erb
<% content_for :title, "Edit #{@shop.name}" %>

<div class="max-w-2xl">
  <%# Back link %>
  <div class="mb-6">
    <%= link_to "← Back to #{@shop.name}", shop_path(@shop),
          class: "text-theme-sm font-medium text-brand-600 hover:text-brand-700" %>
  </div>

  <%# Page header %>
  <div class="mb-6">
    <h1 class="text-xl font-semibold text-gray-900">Edit <%= @shop.name %></h1>
    <p class="mt-0.5 text-theme-sm text-gray-500">Changes are saved in tessera-core via the internal API.</p>
  </div>

  <div class="card">
    <%= form_with url: shop_path(@shop), method: :patch, class: "space-y-5" do |f| %>
      <div>
        <%= label_tag "shop[notification_url]", "Notification URL", class: "form-label" %>
        <p class="text-xs text-gray-500 mt-0.5">Must be an HTTPS URL. Leave blank to disable webhooks.</p>
        <%= url_field_tag "shop[notification_url]",
              params.dig(:shop, :notification_url) || @shop.notification_url,
              placeholder: "https://your-server.com/webhooks",
              class: "form-input mt-1" %>
      </div>

      <div class="flex items-center gap-3">
        <%= hidden_field_tag "shop[test_mode]", "0" %>
        <%= check_box_tag "shop[test_mode]", "1",
              params.key?(:shop) ? ActiveModel::Type::Boolean.new.cast(params.dig(:shop, :test_mode)) : @shop.test_mode?,
              class: "h-4 w-4 rounded border-gray-300 text-brand-500 focus:ring-brand-500" %>
        <%= label_tag "shop[test_mode]", "Test mode", class: "text-theme-sm font-medium text-gray-700 cursor-pointer" %>
      </div>

      <div class="flex flex-col gap-3 pt-2 sm:flex-row">
        <%= f.submit "Save changes", class: "btn btn-primary w-full sm:w-auto" %>
        <%= link_to "Cancel", shop_path(@shop), class: "btn btn-secondary w-full sm:w-auto" %>
      </div>
    <% end %>
  </div>
</div>
```

- [ ] **Run tests**

```bash
bundle exec rspec --format progress
# Expected: 194 examples, 0 failures
```

- [ ] **Commit**

```bash
git add app/views/shops/index.html.erb app/views/shops/show.html.erb \
        app/views/shops/new.html.erb app/views/shops/edit.html.erb
git commit -m "style: theme shops views (MH-32)"
```

---

## Task 10: Shops credentials partial

**Files:**
- Modify: `app/views/shops/_credentials.html.erb`

- [ ] **Rewrite** — replace all badge inline classes with `badge-*`, apply table styling:

```erb
<section class="mt-8 border-t border-gray-200 pt-8">
  <div class="flex items-start justify-between gap-4">
    <div>
      <h2 class="text-base font-semibold text-gray-900">API credentials</h2>
      <p class="mt-0.5 text-theme-sm text-gray-500">
        Per-shop keys for integrating with tessera-core. Secret keys are shown only once at generation.
      </p>
    </div>
    <% if ShopPolicy.new(current_user, shop).generate_credential? %>
      <%= button_to "Generate credentials",
            shop_credential_path(shop),
            method: :post,
            class: "btn btn-primary shrink-0",
            data: { turbo_confirm: "Generate new API credentials? Any existing active key may need to be rotated in your integration." } %>
    <% end %>
  </div>

  <% if defined?(@credentials_error) && @credentials_error.present? %>
    <p class="mt-4 text-theme-sm text-error-600">Could not load credentials: <%= @credentials_error %></p>
  <% elsif @credentials.blank? %>
    <p class="mt-4 text-theme-sm text-gray-500">No credentials yet. Generate a pair to start integrating.</p>
  <% else %>
    <div class="mt-4 card overflow-hidden p-0">
      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500">Public key</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500">Status</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500">Signing</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500">Created</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-gray-500">Last used</th>
              <th class="relative px-4 py-3"><span class="sr-only">Actions</span></th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200 bg-white">
            <% @credentials.each do |cred| %>
              <% revoked = cred["status"].to_s == "revoked" %>
              <% credential_id = cred["id"].presence || cred["pk"] %>
              <tr>
                <td class="px-4 py-3 text-theme-sm font-mono text-gray-900"><%= cred["pk"] %></td>
                <td class="px-4 py-3">
                  <span class="<%= revoked ? 'badge badge-gray' : 'badge badge-success' %>">
                    <%= cred["status"].presence&.titleize || "Unknown" %>
                  </span>
                </td>
                <td class="px-4 py-3 text-theme-sm text-gray-700">
                  <%= cred["signing_required"] ? "Required" : "Optional" %>
                </td>
                <td class="px-4 py-3 text-theme-sm text-gray-500"><%= cred["created"].presence || "—" %></td>
                <td class="px-4 py-3 text-theme-sm text-gray-500"><%= cred["last_used"].presence || "—" %></td>
                <td class="px-4 py-3 text-right">
                  <% if !revoked && ShopPolicy.new(current_user, shop).revoke_credential? %>
                    <%= button_to "Revoke",
                          shop_credential_revoke_path(shop, credential_id),
                          method: :delete,
                          class: "table-action text-error-600 hover:text-error-700",
                          data: { turbo_confirm: "Revoke credential #{cred['pk']}? This cannot be undone." } %>
                  <% end %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
  <% end %>
</section>
```

- [ ] **Run tests**

```bash
bundle exec rspec --format progress
# Expected: 194 examples, 0 failures
```

---

## Task 11: Merchant onboard form

**Files:**
- Modify: `app/views/merchants/new.html.erb`

- [ ] **Rewrite the view**

```erb
<% content_for :title, "Onboard a merchant" %>

<div class="max-w-2xl">
  <%# Page header %>
  <div class="mb-6">
    <h1 class="text-xl font-semibold text-gray-900">Onboard a merchant</h1>
    <p class="mt-0.5 text-theme-sm text-gray-500">
      Creates the merchant and its first shop in tessera-core, and invites the first admin.
    </p>
  </div>

  <div class="card">
    <%= form_with url: merchants_path, method: :post, class: "space-y-8" do |f| %>

      <section class="space-y-4">
        <h2 class="text-xs font-semibold uppercase tracking-wider text-gray-500">Merchant</h2>
        <div>
          <%= label_tag "merchant[name]", "Name", class: "form-label" %>
          <%= text_field_tag "merchant[name]", params.dig(:merchant, :name), class: "form-input mt-1" %>
        </div>
        <div>
          <%= label_tag "merchant[company_name]", "Company name", class: "form-label" %>
          <%= text_field_tag "merchant[company_name]", params.dig(:merchant, :company_name),
                class: "form-input mt-1" %>
        </div>
        <div>
          <%= label_tag "merchant[country]", "Country (ISO-2)", class: "form-label" %>
          <%= text_field_tag "merchant[country]", params.dig(:merchant, :country),
                maxlength: 2, class: "form-input mt-1" %>
        </div>
      </section>

      <section class="space-y-4 border-t border-gray-200 pt-6">
        <h2 class="text-xs font-semibold uppercase tracking-wider text-gray-500">First shop</h2>
        <div>
          <%= label_tag "shop[name]", "Shop name", class: "form-label" %>
          <%= text_field_tag "shop[name]", params.dig(:shop, :name), class: "form-input mt-1" %>
        </div>
        <div>
          <%= label_tag "shop[country]", "Territory (ISO-2)", class: "form-label" %>
          <%= text_field_tag "shop[country]", params.dig(:shop, :country),
                maxlength: 2, class: "form-input mt-1" %>
        </div>
      </section>

      <section class="space-y-4 border-t border-gray-200 pt-6">
        <h2 class="text-xs font-semibold uppercase tracking-wider text-gray-500">First admin</h2>
        <div>
          <%= label_tag "admin[email]", "Admin email", class: "form-label" %>
          <p class="text-xs text-gray-500 mt-0.5">They'll receive an email to set their password.</p>
          <%= email_field_tag "admin[email]", params.dig(:admin, :email), class: "form-input mt-1" %>
        </div>
      </section>

      <div class="flex flex-col gap-3 border-t border-gray-200 pt-6 sm:flex-row">
        <%= f.submit "Onboard merchant", class: "btn btn-primary w-full sm:w-auto" %>
        <%= link_to "Cancel", authenticated_root_path, class: "btn btn-secondary w-full sm:w-auto" %>
      </div>

    <% end %>
  </div>
</div>
```

- [ ] **Run tests**

```bash
bundle exec rspec --format progress
# Expected: 194 examples, 0 failures
```

- [ ] **Commit**

```bash
git add app/views/merchants/new.html.erb app/views/shops/_credentials.html.erb
git commit -m "style: theme merchant onboard form and credentials partial (MH-32)"
```

---

## Task 12: Errors and credentials show-once

**Files:**
- Modify: `app/views/errors/forbidden.html.erb`
- Modify: `app/views/shop_credentials/show_once.html.erb`

- [ ] **Rewrite `errors/forbidden.html.erb`**

```erb
<div class="flex min-h-screen items-center justify-center bg-gray-50 px-4">
  <div class="w-full max-w-md text-center">
    <div class="card">
      <p class="text-5xl font-bold text-gray-900">403</p>
      <h1 class="mt-3 text-lg font-semibold text-gray-900">Access denied</h1>
      <p class="mt-2 text-theme-sm text-gray-500">
        You don't have permission to view this page.
      </p>
      <div class="mt-6">
        <%= link_to "Go back", :back, class: "btn btn-secondary" %>
      </div>
    </div>
  </div>
</div>
```

- [ ] **Rewrite `shop_credentials/show_once.html.erb`**

```erb
<% content_for :title, "Save your credentials" %>

<div class="max-w-2xl">
  <%# Back link %>
  <div class="mb-6">
    <%= link_to "← Back to #{@shop.name}", shop_path(@shop),
          class: "text-theme-sm font-medium text-brand-600 hover:text-brand-700" %>
  </div>

  <%# Warning banner %>
  <div class="flash-alert mb-6">
    <strong>Save these now.</strong>
    The secret key and signing secret are shown exactly once and cannot be retrieved again.
  </div>

  <%# Page header %>
  <div class="mb-6">
    <h1 class="text-xl font-semibold text-gray-900">Your new API credentials</h1>
    <p class="mt-0.5 text-theme-sm text-gray-500">
      Shop <span class="font-mono"><%= @shop.shop_id %></span>
    </p>
  </div>

  <div class="card space-y-6">
    <% [
      ["Public key (pk_)",  @credential["pk"],             false],
      ["Secret key (sk_)",  @credential["sk"],             true],
      ["Signing secret",    @credential["signing_secret"], true],
    ].each do |label, value, _sensitive| %>
      <div data-controller="clipboard">
        <dt class="text-xs font-semibold uppercase tracking-wider text-gray-500"><%= label %></dt>
        <dd class="mt-2">
          <code class="block rounded-lg bg-gray-100 px-3 py-2 text-theme-sm font-mono break-all"
                data-clipboard-target="source"><%= value %></code>
          <div class="mt-2 flex items-center gap-2">
            <button type="button" data-action="clipboard#copy"
                    class="btn btn-secondary text-xs py-1.5 px-3">
              Copy
            </button>
            <span class="text-xs text-gray-500" data-clipboard-target="feedback"></span>
          </div>
        </dd>
      </div>
    <% end %>
  </div>

  <%# Integration guide %>
  <div class="mt-6 card bg-gray-50 space-y-2 text-theme-sm text-gray-700">
    <h2 class="font-semibold text-gray-900">How to integrate</h2>
    <p>Send the secret key as a Bearer token on every request to tessera-core
      (<code class="text-xs">Authorization: Bearer &lt;sk_…&gt;</code>).
    </p>
    <p>Use the public key only where you need to identify the credential (logs, support, dashboards).</p>
    <p>If request signing is enabled for this shop, sign each request with the signing secret:
       HMAC over timestamp, HTTP method, path, and body.
    </p>
    <p>Store both secrets in your server-side configuration — never in a browser or mobile app.</p>
  </div>

  <div class="mt-6">
    <%= link_to "Done — back to shop", shop_path(@shop), class: "btn btn-primary" %>
  </div>
</div>
```

- [ ] **Run tests**

```bash
bundle exec rspec --format progress
# Expected: 194 examples, 0 failures
```

- [ ] **Commit**

```bash
git add app/views/errors/ app/views/shop_credentials/ app/views/payments/_status_badge.html.erb
git commit -m "style: theme errors, credentials show-once, and status badge (MH-32)"
```

---

## Task 13: Final sweep and rebuild

- [ ] **Rebuild CSS to pick up all new classes used in views**

```bash
bin/rails tailwindcss:build
```

- [ ] **Run full test suite one final time**

```bash
bundle exec rspec --format progress
# Expected: 194 examples, 0 failures
```

- [ ] **Final commit — spec and plan docs**

```bash
git add docs/
git commit -m "docs: add MH-32 spec and implementation plan"
```
