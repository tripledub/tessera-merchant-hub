# Payment Detail Modal (MH-45) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clicking "View" on the payments index opens a Turbo Frame modal with view-only payment details, while direct visits to `/payments/:id` continue to render the full-page show view unchanged.

**Architecture:** An empty `<turbo-frame id="payment-modal">` in the application layout acts as the modal mount point. The View link targets this frame; the show page includes a matching frame that renders a modal overlay partial. A `ModalController` Stimulus controller handles Escape, backdrop click, scroll lock, and close. No new controller action needed.

**Tech Stack:** Rails 8, Hotwire Turbo Frames, Stimulus, TailAdmin CSS utilities (`card`, `badge-*`, `btn-secondary`)

---

## File Map

| File | Action |
|---|---|
| `app/javascript/controllers/modal_controller.js` | Create — Escape, backdrop click, scroll lock, close |
| `app/views/payments/_modal_detail.html.erb` | Create — modal overlay HTML with payment detail fields |
| `app/views/payments/show.html.erb` | Modify — add `<turbo-frame id="payment-modal">` at top |
| `app/views/layouts/application.html.erb` | Modify — add empty `<turbo-frame id="payment-modal">` before `</body>` |
| `app/views/payments/index.html.erb` | Modify — View link targets `payment-modal` frame |

---

### Task 1: ModalController

**Files:**
- Create: `app/javascript/controllers/modal_controller.js`

No JS test infrastructure exists. Verification is done by running the full RSpec suite to confirm nothing broke.

- [ ] **Step 1: Create the controller**

```js
// app/javascript/controllers/modal_controller.js
// Manages a Turbo Frame modal: scroll lock, Escape/backdrop close.
// Usage:
//   <div data-controller="modal" data-action="keydown.esc@window->modal#close">
//     <div data-action="click->modal#close"><!-- backdrop --></div>
//     <!-- modal card — stop propagation so clicks inside don't close -->
//   </div>
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    document.body.style.overflow = "hidden"
  }

  disconnect() {
    document.body.style.overflow = ""
  }

  close() {
    const frame = document.getElementById("payment-modal")
    if (frame) {
      frame.src = ""
      frame.innerHTML = ""
    }
  }
}
```

`eagerLoadControllersFrom` in `app/javascript/controllers/index.js` auto-registers this as `modal` — no further wiring needed.

- [ ] **Step 2: Run specs to confirm nothing broke**

```bash
bundle exec rspec spec/requests/payments_spec.rb
```

Expected: all existing examples pass.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/modal_controller.js
git commit -m "feat(MH-45): add Stimulus ModalController"
```

---

### Task 2: Modal detail partial

**Files:**
- Create: `app/views/payments/_modal_detail.html.erb`

This partial renders the full modal overlay (backdrop + card). It is only ever rendered inside `<turbo-frame id="payment-modal">` on the show page — never rendered standalone.

**Context you need:**
- `payment` is passed as a local variable
- TailAdmin utilities in use: `card`, `badge badge-*`, `text-theme-sm`, `form-label`
- Status badge partial: `render partial: "payments/status_badge", locals: { status: payment.status }`
- `number_to_currency(payment.amount / 100.0, unit: payment.currency + " ")` formats amounts
- Closing the modal: call `modal#close` action — this clears the Turbo Frame entirely

- [ ] **Step 1: Create the partial**

```erb
<%# app/views/payments/_modal_detail.html.erb %>
<%# Full-screen backdrop + centred card. Rendered inside <turbo-frame id="payment-modal">. %>
<div class="fixed inset-0 z-[9999] flex items-center justify-center px-4"
     data-controller="modal"
     data-action="keydown.esc@window->modal#close">

  <%# Backdrop — click closes modal %>
  <div class="absolute inset-0 bg-gray-900/60"
       data-action="click->modal#close"
       aria-hidden="true"></div>

  <%# Modal card — stop propagation so clicks inside don't trigger backdrop close %>
  <div class="relative w-full max-w-lg"
       data-action="click->modal#close:stop">
    <div class="card">

      <%# Header %>
      <div class="mb-4 flex items-start justify-between gap-4">
        <div>
          <p class="text-xs font-semibold uppercase tracking-wider text-gray-500">Payment</p>
          <p class="mt-0.5 font-mono text-theme-sm text-gray-900 break-all"><%= payment.id %></p>
        </div>
        <div class="flex items-center gap-3 shrink-0">
          <%= render partial: "payments/status_badge", locals: { status: payment.status } %>
          <button type="button"
                  class="text-gray-400 hover:text-gray-600"
                  data-action="click->modal#close"
                  aria-label="Close">
            <svg class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
              <path d="M6.28 5.22a.75.75 0 0 0-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 1 0 1.06 1.06L10 11.06l3.72 3.72a.75.75 0 1 0 1.06-1.06L11.06 10l3.72-3.72a.75.75 0 0 0-1.06-1.06L10 8.94 6.28 5.22Z"/>
            </svg>
          </button>
        </div>
      </div>

      <%# Detail fields %>
      <dl class="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <div>
          <dt class="text-xs font-semibold uppercase tracking-wider text-gray-500">Amount</dt>
          <dd class="mt-1 text-lg font-semibold text-gray-900">
            <%= number_to_currency(payment.amount / 100.0, unit: payment.currency + " ") %>
          </dd>
        </div>

        <div>
          <dt class="text-xs font-semibold uppercase tracking-wider text-gray-500">Shop</dt>
          <dd class="mt-1 text-theme-sm font-mono text-gray-900"><%= payment.shop_id %></dd>
        </div>

        <% if payment.merchant_reference.present? %>
          <div>
            <dt class="text-xs font-semibold uppercase tracking-wider text-gray-500">Reference</dt>
            <dd class="mt-1 text-theme-sm font-mono text-gray-900"><%= payment.merchant_reference %></dd>
          </div>
        <% end %>

        <div>
          <dt class="text-xs font-semibold uppercase tracking-wider text-gray-500">Created</dt>
          <dd class="mt-1 text-theme-sm text-gray-900">
            <%= payment.inserted_at&.strftime("%d %b %Y at %H:%M UTC") %>
          </dd>
        </div>

        <% if payment.idempotency_key.present? %>
          <div class="sm:col-span-2">
            <dt class="text-xs font-semibold uppercase tracking-wider text-gray-500">Idempotency Key</dt>
            <dd class="mt-1 text-theme-sm font-mono text-gray-900 break-all"><%= payment.idempotency_key %></dd>
          </div>
        <% end %>
      </dl>

    </div>
  </div>
</div>
```

- [ ] **Step 2: Run specs**

```bash
bundle exec rspec spec/requests/payments_spec.rb
```

Expected: all examples pass (partial is not exercised by request specs — this just confirms nothing is broken).

- [ ] **Step 3: Commit**

```bash
git add app/views/payments/_modal_detail.html.erb
git commit -m "feat(MH-45): add payment modal detail partial"
```

---

### Task 3: Wire Turbo Frame into show, layout, and index

**Files:**
- Modify: `app/views/payments/show.html.erb`
- Modify: `app/views/layouts/application.html.erb`
- Modify: `app/views/payments/index.html.erb`

**Context — current `show.html.erb` structure:**

```erb
<% content_for :title, "Payment" %>

<div class="max-w-4xl">
  <%# Back link %>
  ...
</div>
```

**Context — current `application.html.erb` ends with:**

```erb
  </body>
</html>
```

**Context — current View link in `index.html.erb`:**

```erb
<%= link_to "View", payment_path(payment.id), class: "table-action", data: { turbo_frame: "_top" } %>
```

- [ ] **Step 1: Add turbo-frame to top of `show.html.erb`**

Insert `<turbo-frame id="payment-modal">` wrapping the modal partial at the very top of the file, before the existing `<div class="max-w-4xl">`. The full file should read:

```erb
<% content_for :title, "Payment" %>

<turbo-frame id="payment-modal">
  <%= render "payments/modal_detail", payment: @payment %>
</turbo-frame>

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

  <%# Actions %>
  <% if PaymentPolicy.new(current_user, @payment).refund? %>
    <div class="mt-6 flex flex-col gap-3 sm:flex-row">
      <% if @payment.status == "succeeded" %>
        <%= button_to "Refund", refund_payment_path(@payment.id),
              method: :post,
              params: { amount: @payment.amount },
              data: { turbo_confirm: "Submit a full refund of #{number_to_currency(@payment.amount / 100.0, unit: @payment.currency + ' ')}?" },
              class: "btn-danger w-full sm:w-auto" %>
      <% end %>
      <% if @payment.status == "authorized" %>
        <%= button_to "Void", void_payment_path(@payment.id),
              method: :post,
              data: { turbo_confirm: "Void this authorisation?" },
              class: "btn-warning w-full sm:w-auto" %>
      <% end %>
    </div>
  <% end %>

  <%# Tab links %>
  <div class="mt-8 border-b border-gray-200">
    <nav class="-mb-px flex gap-6">
      <span class="border-b-2 border-brand-500 inline-flex items-center min-h-11 text-theme-sm font-medium text-brand-600">Details</span>
      <%= link_to "Timeline", payment_timeline_path(@payment.id),
            class: "border-b-2 border-transparent inline-flex items-center min-h-11 text-theme-sm font-medium text-gray-500 hover:text-gray-700 hover:border-gray-300" %>
    </nav>
  </div>
</div>
```

- [ ] **Step 2: Add empty turbo-frame to `application.html.erb`**

Find the closing `</body>` tag in `app/views/layouts/application.html.erb` and insert the empty frame just before it:

```erb
    <turbo-frame id="payment-modal"></turbo-frame>
  </body>
</html>
```

- [ ] **Step 3: Update View link in `index.html.erb`**

Find this line in `app/views/payments/index.html.erb`:

```erb
              <%= link_to "View", payment_path(payment.id), class: "table-action", data: { turbo_frame: "_top" } %>
```

Replace with:

```erb
              <%= link_to "View", payment_path(payment.id), class: "table-action", data: { turbo_frame: "payment-modal" } %>
```

- [ ] **Step 4: Run the full test suite**

```bash
bundle exec rspec
```

Expected: 197 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/views/payments/show.html.erb \
        app/views/layouts/application.html.erb \
        app/views/payments/index.html.erb
git commit -m "feat(MH-45): wire Turbo Frame modal into show, layout, and index"
```
