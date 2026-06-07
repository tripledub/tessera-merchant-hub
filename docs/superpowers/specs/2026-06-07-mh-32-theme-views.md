# MH-32: Theme Application Across All Views

**Date:** 2026-06-07  
**Ticket:** MH-32  
**Branch:** feat/MH-30-tailwind-theme (continuation)

---

## Goal

Apply the TailAdmin theme consistently across every view in MerchantHub — auth screens (Devise), payments, shops, merchant onboarding, errors, and credentials. Purely visual; no behaviour changes.

---

## Context

MH-30 introduced the compiled TailAdmin CSS pipeline (`app/assets/tailwind/application.css` → `app/assets/builds/tailwind.css`) with a full `@theme` token set and `@utility` classes. MH-31 added the dark sidebar layout. MH-32 makes the existing views consume those utilities consistently.

The old `app/assets/tailwind/application.css` defined `btn-ghost`, `form-select`, and `table-action`. These were removed when we replaced it with the TailAdmin CSS. These classes must be reinstated as utilities or replaced in views before any page will render correctly.

---

## Design Decisions

### Auth screens
- **Layout:** Centred card on `bg-gray-50` full-height page — no sidebar, no header (unauthenticated branch of application layout already handles this)
- **Pattern:** Single shared `_auth_card.html.erb` partial wrapping title + form; Devise views rendered inside it
- **Rationale:** Centred card translates cleanly to Hotwire Native web view; split-panel adds complexity for no gain

### Page header pattern (authenticated views)
- **Pattern:** Inline page header block at top of each view's `<main>` content — `<h1>` + optional subtitle + optional right-side action
- **Rationale:** More flexible than hoisting to sticky header; allows per-page action buttons, subtitles, back links above the title

### Missing utilities to restore
| Old class | Replacement |
|---|---|
| `btn-ghost` | `btn-secondary` (already in new CSS) — update all view usages |
| `form-select` | New `@utility form-select` — same base as `form-input` with appearance override |
| `table-action` | New `@utility table-action` — brand-coloured inline link |

---

## Scope

### In scope
- `app/assets/tailwind/application.css` — add `form-select`, `table-action` utilities
- All Devise views: `sessions/new`, `passwords/new`, `passwords/edit`, `registrations/edit`, `unlocks/new`, `confirmations/new`
- `layouts/_auth_card.html.erb` — new shared partial
- `payments/index`, `payments/show`, `payments/_status_badge`
- `shops/index`, `shops/show`, `shops/new`, `shops/edit`, `shops/_credentials`
- `merchants/new`
- `errors/forbidden`
- `shop_credentials/show_once`
- Replace all `btn-ghost` → `btn-secondary`, `text-indigo-600` back links → `text-brand-500`

### Out of scope
- `devise/registrations/new` — self-registration not exposed in this app
- Dashboard widgets (MH-33/34)
- Pagination redesign
- New behaviour of any kind

---

## Utilities to Add

```css
/* form-select: like form-input but for <select> elements */
@utility form-select {
  @apply block w-full rounded-lg border border-gray-300 bg-white px-4 py-2.5 text-theme-sm text-gray-900
         focus:border-brand-500 focus:ring-2 focus:ring-brand-500/20 focus:outline-none
         dark:border-gray-700 dark:bg-gray-900 dark:text-white dark:focus:border-brand-400;
  appearance: none;
}

/* table-action: brand-coloured inline link for table row actions */
@utility table-action {
  @apply text-theme-sm font-medium text-brand-600 hover:text-brand-700 min-h-11 inline-flex items-center;
}
```

---

## Auth Card Structure

```erb
<%# layouts/_auth_card.html.erb %>
<div class="flex min-h-screen items-center justify-center bg-gray-50 px-4 py-12">
  <div class="w-full max-w-md">
    <%# Brand mark %>
    <div class="mb-8 flex flex-col items-center gap-3">
      <div class="flex h-12 w-12 items-center justify-center rounded-xl bg-brand-500">
        <%# card SVG %>
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

Each Devise view renders its form inside this partial via `render "layouts/auth_card", title: "..." do ... end`.

---

## Status Badge Mapping

```ruby
badge_class = {
  "succeeded" => "badge badge-success",
  "failed"    => "badge badge-error",
  "pending"   => "badge badge-warning",
  "refunded"  => "badge badge-info",
  "voided"    => "badge badge-gray"
}.fetch(status, "badge badge-gray")
```

Shop mode badges: `test_mode? ? "badge badge-warning" : "badge badge-success"`  
Credential status: `revoked ? "badge badge-gray" : "badge badge-success"`

---

## Testing Strategy

No new behaviour — existing 194 request/model specs provide regression coverage. After each task, run `bundle exec rspec` and confirm 194 examples, 0 failures. No new tests needed for purely visual changes.
