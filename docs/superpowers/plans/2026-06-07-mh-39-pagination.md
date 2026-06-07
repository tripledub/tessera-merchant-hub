# MH-39: Payment List Pagination Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce payment list page size from 50 to 25 and add request spec coverage for pagination, including combined filter + pagination behaviour.

**Architecture:** Pagy is already installed and wired — `ApplicationController` includes `Pagy::Method`, the controller calls `pagy(:offset, scope, limit: 50)`, and the view renders `@pagy.series_nav` inside the Turbo Frame. The only code change is `limit: 50` → `limit: 25`. Pagy's `series_nav` automatically preserves existing query params (e.g. `?status=succeeded`) when generating page links, so filter + pagination works with no extra wiring.

**Tech Stack:** Rails 8, Pagy 43.x (offset mode), RSpec request specs

---

## File Map

| File | Action |
|---|---|
| `app/controllers/payments_controller.rb` | Modify — change `limit: 50` to `limit: 25` |
| `spec/requests/payments_spec.rb` | Modify — add pagination request specs |

---

### Task 1: Change page size to 25

**Files:**
- Modify: `app/controllers/payments_controller.rb` (line 8)

Current line:
```ruby
@pagy, @payments = pagy(:offset, scope, limit: 50)
```

- [ ] **Step 1: Update the limit**

Change line 8 of `app/controllers/payments_controller.rb` to:

```ruby
@pagy, @payments = pagy(:offset, scope, limit: 25)
```

- [ ] **Step 2: Run specs**

```bash
bundle exec rspec spec/requests/payments_spec.rb
```

Expected: all existing examples pass.

- [ ] **Step 3: Commit**

```bash
git add app/controllers/payments_controller.rb
git commit -m "feat(MH-39): reduce payment list page size to 25"
```

---

### Task 2: Add pagination request specs

**Files:**
- Modify: `spec/requests/payments_spec.rb`

**Context:**
- Existing fixtures use `let_it_be` — `own_payment` (shop_abc, succeeded) and `other_payment` (shop_xyz, failed)
- The `tessera_payment` factory uses a raw SQL `to_create` block to bypass `ReadOnlyRecord`
- To test pagination we need more than 25 payments for a shop — create 26 payments for `shop_abc` in a `let_it_be` block scoped to the pagination context
- PSP admin sees all payments; merchant admin sees only own shop payments
- Pagy adds `?page=2` to the URL for subsequent pages
- Page 2 should return 200 even if empty (pagy handles this gracefully)

- [ ] **Step 1: Add pagination context to the spec**

Add the following context inside the existing `describe "GET /payments"` block, after the `"when filtering by status"` context and before the `"when unauthenticated"` context:

```ruby
context "when paginating" do
  # Create 26 payments for shop_abc so page 2 exists (page size is 25)
  let_it_be(:paginated_payments) do
    26.times.map do |i|
      create(:tessera_payment,
        shop_id: "shop_abc",
        status: "succeeded",
        inserted_at: Time.current - i.hours,
        updated_at:  Time.current - i.hours)
    end
  end

  before { sign_in psp_admin }

  it "returns 200 for page 1" do
    get payments_path, params: { page: 1 }
    expect(response).to have_http_status(:ok)
  end

  it "returns 200 for page 2" do
    get payments_path, params: { page: 2 }
    expect(response).to have_http_status(:ok)
  end

  it "returns 200 for page 1 with a status filter applied" do
    get payments_path, params: { page: 1, status: "succeeded" }
    expect(response).to have_http_status(:ok)
  end
end
```

- [ ] **Step 2: Run only the new specs to confirm they pass**

```bash
bundle exec rspec spec/requests/payments_spec.rb -e "when paginating"
```

Expected: 3 examples, 0 failures.

- [ ] **Step 3: Run the full payments spec**

```bash
bundle exec rspec spec/requests/payments_spec.rb
```

Expected: all examples pass.

- [ ] **Step 4: Commit**

```bash
git add spec/requests/payments_spec.rb
git commit -m "test(MH-39): add pagination request specs"
```
