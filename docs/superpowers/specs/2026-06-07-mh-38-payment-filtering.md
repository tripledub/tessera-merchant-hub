# MH-38: Payment List Filtering

**Date:** 2026-06-07
**Ticket:** MH-38
**Branch:** to be created

---

## Goal

Add a Stimulus-powered auto-submitting status filter to the payments index. Selecting a status instantly updates the table via a Turbo Frame — no full page reload, no Submit button required.

---

## Scope

V1 covers status filter only. Date range, reference search, and amount range are out of scope for this iteration.

---

## Architecture

The existing `PaymentsController#index` already applies `where(status: params[:status])` when the param is present — **no controller changes needed**.

The view gains two Hotwire additions:

1. **Turbo Frame** (`<turbo-frame id="payments-table">`) wrapping the table and pagination. When the form submits, Turbo replaces only this frame.
2. **Stimulus `FilterController`** attached to the filter form. Listens for `change` on the status `<select>` and calls `this.element.requestSubmit()`, triggering the form GET without a full navigation.

The form uses `data-turbo-action="advance"` so the URL in the browser address bar updates correctly — making filtered views bookmarkable and shareable.

---

## Components

### `app/javascript/controllers/filter_controller.js` (new)

```js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
```

Registered automatically by Stimulus's `eagerLoadControllersFrom` (already wired in `application.js`).

### `app/views/payments/index.html.erb` (modified)

- Add `data-controller="filter"` and `data-turbo-action="advance"` to the existing `form_with`.
- Add `data-action="change->filter#submit"` to the status `<select>`.
- Remove the `Filter` submit button (auto-submit replaces it).
- Keep the `Clear` link — it navigates to `payments_path` with no params, which already works and sits outside the Turbo Frame.
- Wrap the table `<div class="card ...">` and the pagination block in `<turbo-frame id="payments-table">`.

---

## URL Behaviour

Filter state lives in the query string (`?status=succeeded`). `data-turbo-action="advance"` pushes a new history entry so back/forward navigation works. Sharing or bookmarking the URL produces the same filtered view.

---

## Request Spec Additions (`spec/requests/payments_spec.rb`)

Four new cases inside the existing `"GET /payments"` block:

| Case | Expected |
|---|---|
| `status=succeeded` as psp_admin | includes succeeded payment, excludes failed |
| `status=failed` as psp_admin | includes failed payment, excludes succeeded |
| `status=voided` (no matching payments) | returns 200, shows empty state |
| `status=` (blank) | same as no filter — returns all |

Note: a `"when filtering by status"` context already exists in the spec; it will be expanded rather than duplicated.

---

## Files Changed

| File | Action |
|---|---|
| `app/javascript/controllers/filter_controller.js` | Create |
| `app/views/payments/index.html.erb` | Modify |
| `spec/requests/payments_spec.rb` | Modify (add filter specs) |

No migrations. No model changes. No policy changes. No new routes.

---

## Out of Scope

- Date range filter
- Reference / order ID search
- Amount range filter
- JS unit tests (no JS test infrastructure exists)
