# Payment Detail Modal

**Date:** 2026-06-07
**Ticket:** MH-45 (pending)
**Branch:** to be created

---

## Goal

Clicking "View" on the payments index opens a modal overlay showing payment details — amount, status, shop, reference, created date, idempotency key — without navigating away from the list. The full-page show view (`/payments/:id`) continues to work for direct visits. No refund/void actions in the modal (view-only for v1).

---

## Architecture

### Turbo Frame modal

An empty `<turbo-frame id="payment-modal">` sits at the bottom of `layouts/application.html.erb` (just before `</body>`), rendering nothing by default.

The "View" link on the index uses `data-turbo-frame="payment-modal"`. When clicked, Turbo loads `payments/:id` and extracts the matching `<turbo-frame id="payment-modal">` from the response — discarding the rest of the show page.

The show view contains both:
1. A `<turbo-frame id="payment-modal">` wrapping a modal overlay partial (`_modal_detail.html.erb`) — used when the page is loaded via the frame
2. The existing full-page content outside the frame — used on direct `/payments/:id` visits (unchanged)

### ModalController (Stimulus)

Attached to the modal overlay element inside `_modal_detail.html.erb`. Responsibilities:
- Close on **Escape** keydown (connected via `keydown.esc@window->modal#close`)
- Close on **backdrop click** (the semi-transparent overlay behind the card)
- **Body scroll lock** while open (`document.body.style.overflow = "hidden"` on connect, restored on disconnect)
- **Close action** clears the Turbo Frame: sets `this.frameElement.src = ""` and `this.frameElement.innerHTML = ""`

### No new controller action

The existing `PaymentsController#show` action serves both modal and full-page requests. The Turbo Frame mechanism handles the difference purely in the view layer.

---

## Components

### `app/javascript/controllers/modal_controller.js` (new)

```js
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

Registered automatically by `eagerLoadControllersFrom`.

### `app/views/payments/_modal_detail.html.erb` (new)

Modal overlay structure:
- Full-screen fixed backdrop (`bg-gray-900/60`) with `data-action="click->modal#close"`
- Centred card (`max-w-lg w-full`) with `data-controller="modal"` and `data-action="keydown.esc@window->modal#close"`
- Close button (×) in the top-right corner calling `modal#close`
- Payment ID in monospace as the modal title
- Detail fields: Amount, Status badge, Shop, Merchant Reference (if present), Created, Idempotency Key
- No Refund/Void buttons (view-only)

### `app/views/payments/show.html.erb` (modified)

Add `<turbo-frame id="payment-modal">` at the top of the file wrapping `_modal_detail`. The existing full-page content (`max-w-4xl` div with back link, header, detail grid, actions, tabs) stays outside the frame and is unchanged.

```erb
<turbo-frame id="payment-modal">
  <%= render "payments/modal_detail", payment: @payment %>
</turbo-frame>

<%# existing full-page content below — unchanged %>
<div class="max-w-4xl">
  ...
</div>
```

### `app/views/layouts/application.html.erb` (modified)

Add empty frame just before `</body>`:

```erb
  <turbo-frame id="payment-modal"></turbo-frame>
</body>
```

### `app/views/payments/index.html.erb` (modified)

Change View link from `data-turbo-frame: "_top"` (the bugfix just applied) to `data-turbo-frame: "payment-modal"`:

```erb
<%= link_to "View", payment_path(payment.id), class: "table-action",
      data: { turbo_frame: "payment-modal" } %>
```

---

## Behaviour

| Scenario | Result |
|---|---|
| Click "View" on payments index | Modal opens with payment details |
| Press Escape | Modal closes, list remains |
| Click backdrop | Modal closes, list remains |
| Click × button | Modal closes, list remains |
| Visit `/payments/:id` directly | Full-page show view (unchanged) |
| Filter then open modal, close modal | List still filtered (URL unchanged) |

---

## Files Changed

| File | Action |
|---|---|
| `app/javascript/controllers/modal_controller.js` | Create |
| `app/views/payments/_modal_detail.html.erb` | Create |
| `app/views/payments/show.html.erb` | Modify — add turbo-frame at top |
| `app/views/layouts/application.html.erb` | Modify — add empty turbo-frame before `</body>` |
| `app/views/payments/index.html.erb` | Modify — View link targets `payment-modal` frame |

No migrations. No model changes. No new routes. No new controller actions. No new request specs (existing `show` specs cover the action; modal is a view concern).

---

## Out of Scope

- Refund / void actions in the modal
- Timeline tab in the modal
- Keyboard focus trap inside the modal
- Animation / transition on open/close
