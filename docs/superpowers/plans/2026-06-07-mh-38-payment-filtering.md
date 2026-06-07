# MH-38: Payment List Filtering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Stimulus auto-submit status filter to the payments index, with the results table wrapped in a Turbo Frame so only the table refreshes on filter change.

**Architecture:** The existing `PaymentsController#index` already handles `params[:status]` — no controller changes needed. A new `FilterController` Stimulus controller calls `requestSubmit()` on the form when the select changes. The table and pagination are wrapped in `<turbo-frame id="payments-table">` so Turbo replaces only that region. `data-turbo-action="advance"` keeps the URL bookmarkable.

**Tech Stack:** Rails 8, Hotwire Turbo Frames, Stimulus, RSpec request specs

---

## File Map

| File | Action |
|---|---|
| `app/javascript/controllers/filter_controller.js` | Create — Stimulus controller with `submit()` action |
| `app/views/payments/index.html.erb` | Modify — add Turbo Frame, wire Stimulus, remove Submit button |
| `spec/requests/payments_spec.rb` | Modify — expand filter specs |

---

### Task 1: Stimulus FilterController

**Files:**
- Create: `app/javascript/controllers/filter_controller.js`

No test for JS (no JS test infrastructure exists in this project). Verification is done by running the full request spec suite to confirm nothing broke.

- [ ] **Step 1: Create the controller**

```js
// app/javascript/controllers/filter_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
```

`eagerLoadControllersFrom` in `app/javascript/controllers/index.js` will automatically register this as `filter` — no further wiring needed.

- [ ] **Step 2: Verify the controller file is discoverable**

```bash
ls app/javascript/controllers/filter_controller.js
```

Expected: file exists.

- [ ] **Step 3: Run specs to confirm nothing broke**

```bash
bundle exec rspec spec/requests/payments_spec.rb
```

Expected: all existing examples pass.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/filter_controller.js
git commit -m "feat(MH-38): add Stimulus FilterController for auto-submit"
```

---

### Task 2: Wire Turbo Frame and Stimulus into the payments index view

**Files:**
- Modify: `app/views/payments/index.html.erb`

**Context — current structure of the filter form (lines ~10–24):**

```erb
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
    <%= f.submit "Filter", class: "btn-primary" %>
    <% if params[:status].present? %>
      <%= link_to "Clear", payments_path, class: "btn-secondary" %>
    <% end %>
  </div>
<% end %>
```

**Context — current structure of the table + pagination (after the form):**

```erb
<%# Table %>
<div class="card overflow-hidden p-0">
  ...table...
</div>

<%# Pagination %>
<% if @pagy.pages > 1 %>
  <div class="mt-4 flex justify-center text-theme-sm">
    <%== @pagy.series_nav %>
  </div>
<% end %>
```

- [ ] **Step 1: Add Stimulus data attributes to the form and remove the Submit button**

Replace the form block with:

```erb
<%= form_with url: payments_path, method: :get,
      data: { controller: "filter", turbo_action: "advance" },
      class: "mb-6 flex flex-col gap-3 sm:flex-row sm:items-end" do |f| %>
  <div class="sm:w-48">
    <%= f.label :status, "Status", class: "form-label" %>
    <%= f.select :status,
          [["All statuses", ""], ["Succeeded", "succeeded"], ["Failed", "failed"],
           ["Pending", "pending"], ["Refunded", "refunded"]],
          { selected: params[:status] },
          class: "form-select mt-1",
          data: { action: "change->filter#submit" } %>
  </div>
  <% if params[:status].present? %>
    <%= link_to "Clear", payments_path, class: "btn-secondary self-end" %>
  <% end %>
<% end %>
```

Key changes:
- `data: { controller: "filter", turbo_action: "advance" }` on the form
- `data: { action: "change->filter#submit" }` on the select
- Removed the `<div class="flex gap-3">` wrapper and `f.submit "Filter"` button
- `Clear` link moved directly into the form (no wrapping div), `self-end` keeps it baseline-aligned

- [ ] **Step 2: Wrap the table and pagination in a Turbo Frame**

Replace the `<%# Table %>` comment through to the end of the pagination block with:

```erb
<turbo-frame id="payments-table">
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
</turbo-frame>
```

- [ ] **Step 3: Run specs**

```bash
bundle exec rspec spec/requests/payments_spec.rb
```

Expected: all existing examples pass.

- [ ] **Step 4: Commit**

```bash
git add app/views/payments/index.html.erb
git commit -m "feat(MH-38): wrap payments table in Turbo Frame, wire filter controller"
```

---

### Task 3: Expand filter request specs

**Files:**
- Modify: `spec/requests/payments_spec.rb`

**Context:** The existing spec has `let_it_be` fixtures:
- `own_payment` — `shop_id: "shop_abc"`, `status: "succeeded"`
- `other_payment` — `shop_id: "shop_xyz"`, `status: "failed"`

There is already a `"when filtering by status"` context. Expand it with the additional cases below.

- [ ] **Step 1: Write the new failing specs**

Replace the existing `"when filtering by status"` context in `spec/requests/payments_spec.rb` with:

```ruby
context "when filtering by status" do
  before { sign_in psp_admin }

  it "returns only succeeded payments when status=succeeded" do
    get payments_path, params: { status: "succeeded" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own_payment.id)
    expect(response.body).not_to include(other_payment.id)
  end

  it "returns only failed payments when status=failed" do
    get payments_path, params: { status: "failed" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(other_payment.id)
    expect(response.body).not_to include(own_payment.id)
  end

  it "returns 200 with empty table when status matches no payments" do
    get payments_path, params: { status: "voided" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No payments found.")
  end

  it "returns all payments when status param is blank" do
    get payments_path, params: { status: "" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own_payment.id)
    expect(response.body).to include(other_payment.id)
  end
end
```

- [ ] **Step 2: Run only these specs to confirm they pass**

```bash
bundle exec rspec spec/requests/payments_spec.rb -e "when filtering by status"
```

Expected: 4 examples, 0 failures.

- [ ] **Step 3: Run the full payments spec**

```bash
bundle exec rspec spec/requests/payments_spec.rb
```

Expected: all examples pass.

- [ ] **Step 4: Commit**

```bash
git add spec/requests/payments_spec.rb
git commit -m "test(MH-38): expand payment filter request specs"
```
