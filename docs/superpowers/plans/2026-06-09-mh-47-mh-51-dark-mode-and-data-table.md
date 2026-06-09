# Dark Mode + Data Table Upgrade (MH-51 + MH-47) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire up dark mode with a persistent toggle, audit every view for correct `dark:` Tailwind classes, and upgrade the payments table with server-side sortable columns.

**Architecture:** Dark mode uses Tailwind v4's `@custom-variant dark (&:is(.dark *))` — a `dark` class on `<html>` activates all dark variants. Alpine.js manages the toggle and persists to `localStorage`. An inline `<script>` in `<head>` applies the class before paint to prevent flash. Sortable columns are server-side (URL params `sort` + `direction`) — no JS sorting — consistent with the existing filter-via-GET pattern.

**Tech Stack:** Rails 8, Tailwind CSS v4 (custom dark variant already configured), Alpine.js (already loaded), Stimulus, Turbo, RSpec request specs.

---

## Codebase orientation

Before starting, read these files to understand what already exists:

- `app/assets/tailwind/application.css` — CSS utilities; badges/cards/forms/flash already have dark: variants. Pagy pagination CSS does NOT yet have dark variants.
- `app/views/layouts/application.html.erb` — body has `dark:bg-gray-950`; no FOCT script yet; Alpine x-data not wired.
- `app/views/layouts/_header.html.erb` — rendered in the authenticated shell; lacks dark: on `bg-white border-gray-200`; needs toggle button.
- `app/views/layouts/_sidebar.html.erb` — already permanently dark (`dark` class hardcoded); no changes needed.
- `app/views/payments/index.html.erb` — toolbar, thead, tbody, filter panel rows all use inline classes WITHOUT dark: variants.
- `app/controllers/payments_controller.rb` — hardcoded `order(inserted_at: :desc)`; no sort params yet.
- `app/helpers/payments_helper.rb` — has `filter_chip_label` and `filter_chip_remove_path`; needs `sort_url` helper.

---

## File map

| File | Change |
|------|--------|
| `app/views/layouts/application.html.erb` | Add FOCT inline `<script>` in `<head>`; add Alpine `x-data` to `<body>` |
| `app/views/layouts/_header.html.erb` | Add `dark:` to header chrome; add sun/moon toggle button |
| `app/views/layouts/_auth_card.html.erb` | Add `dark:` to page bg and title |
| `app/views/payments/index.html.erb` | Add all missing `dark:` inline classes; add sortable `<th>` links |
| `app/views/payments/_filter_chips.html.erb` | Add `dark:` to chip border and clear-all link |
| `app/views/payments/_modal_detail.html.erb` | Add `dark:` to `dt`/`dd` text colours |
| `app/assets/tailwind/application.css` | Add dark variants to `.pagy.series-nav` CSS |
| `app/controllers/payments_controller.rb` | Add `SORTABLE_COLUMNS`, `SORT_DIRECTIONS`, `apply_sort` method |
| `app/helpers/payments_helper.rb` | Add `sort_url` helper |
| `spec/requests/payments_spec.rb` | Add sort request specs |

---

## Task 1: FOCT prevention + Alpine darkMode on body (MH-51)

**Files:**
- Modify: `app/views/layouts/application.html.erb`

**Context:** The dark `class` must be on `<html>` before the browser paints. An inline `<script>` (synchronous, no `defer`) in `<head>` reads `localStorage` and sets the class immediately. Alpine.js is already loaded via importmap (`app/javascript/application.js`). We add `x-data` to `<body>` to make `darkMode` available to all child elements including the toggle button.

- [ ] **Step 1: Add FOCT inline script and Alpine x-data**

Replace `application.html.erb` with:

```erb
<!DOCTYPE html>
<html>
  <head>
    <title><%= content_for(:title) || t('app.title') %></title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="application-name" content="<%= t('app.title') %>">
    <meta name="mobile-web-app-capable" content="yes">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>

    <%= yield :head %>

    <link rel="icon" href="/icon.png" type="image/png">
    <link rel="icon" href="/icon.svg" type="image/svg+xml">
    <link rel="apple-touch-icon" href="/icon.png">

    <%= stylesheet_link_tag "tailwind", "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>

    <%# Dark mode: apply before paint to prevent flash of wrong theme.
        Defaults to dark if no preference stored yet. %>
    <script>
      (function () {
        var stored = localStorage.getItem("darkMode");
        var isDark = stored !== null ? JSON.parse(stored) : true;
        if (isDark) {
          document.documentElement.classList.add("dark");
        } else {
          document.documentElement.classList.remove("dark");
        }
      })();
    </script>
  </head>

  <%# x-data makes darkMode reactive state available to all children,
      including the toggle button in _header.html.erb %>
  <body class="bg-gray-50 font-outfit antialiased dark:bg-gray-950"
        x-data="{ darkMode: JSON.parse(localStorage.getItem('darkMode') ?? 'true') }">

    <% if user_signed_in? %>
      <%# ── Authenticated shell: sidebar + header + content ──────────────── %>
      <div data-controller="sidebar" class="flex h-screen overflow-hidden">

        <%= render "layouts/sidebar" %>

        <%# Mobile overlay scrim %>
        <div data-sidebar-target="overlay"
             data-action="click->sidebar#close"
             class="fixed inset-0 z-[9998] bg-gray-900/50 hidden lg:hidden"></div>

        <%# Main content column %>
        <div class="flex min-w-0 flex-1 flex-col overflow-hidden">
          <%= render "layouts/header" %>

          <main class="flex-1 overflow-y-auto p-4 sm:p-6 lg:p-8">
            <% if flash.any? %>
              <div class="mb-6 space-y-3">
                <%= render "layouts/flash" %>
              </div>
            <% end %>
            <%= yield %>
          </main>
        </div>

      </div>

    <% else %>
      <%# ── Unauthenticated: full-page (sign in, password reset, etc.) ───── %>
      <main class="min-h-screen">
        <% if flash.any? %>
          <div class="mx-auto max-w-md px-4 pt-6 space-y-3">
            <%= render "layouts/flash" %>
          </div>
        <% end %>
        <%= yield %>
      </main>
    <% end %>

    <turbo-frame id="payment-modal"></turbo-frame>
  </body>
</html>
```

- [ ] **Step 2: Verify no test breakage**

```bash
bundle exec rspec spec/requests/sessions_spec.rb --format documentation
```

Expected: all pass (no layout changes affect session logic).

- [ ] **Step 3: Commit**

```bash
git add app/views/layouts/application.html.erb
git commit -m "feat(MH-51): add FOCT dark mode script and Alpine darkMode state"
```

---

## Task 2: Dark toggle button + header dark chrome (MH-51)

**Files:**
- Modify: `app/views/layouts/_header.html.erb`

**Context:** The header currently has `bg-white border-b border-gray-200` with no dark variants. We add `dark:bg-gray-900 dark:border-gray-800` and insert a sun/moon toggle button. The button uses Alpine `@click` to flip `darkMode`, toggle the `dark` class on `<html>`, and persist to `localStorage`. Sun icon shows in dark mode (`hidden dark:block`); moon icon shows in light mode (`dark:hidden`). The SVG paths come directly from `../src/partials/header.html` — copy them exactly.

- [ ] **Step 1: Replace `_header.html.erb`**

```erb
<%# Sticky top header — sits above the main content column. %>
<header class="sticky top-0 z-[999] flex h-16 items-center justify-between border-b border-gray-200 bg-white
               px-4 sm:px-6 shadow-theme-xs dark:border-gray-800 dark:bg-gray-900">

  <%# Left: hamburger / collapse toggle %>
  <button type="button"
          data-action="click->sidebar#toggle"
          class="flex h-10 w-10 items-center justify-center rounded-lg border border-gray-200 text-gray-500
                 hover:bg-gray-100 hover:text-gray-700 dark:border-gray-800 dark:text-gray-400
                 dark:hover:bg-gray-800"
          aria-label="<%= t('layouts.navigation.toggle_sidebar') %>">
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor"
         stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="h-5 w-5" aria-hidden="true">
      <line x1="3" y1="6"  x2="21" y2="6"/>
      <line x1="3" y1="12" x2="15" y2="12"/>
      <line x1="3" y1="18" x2="21" y2="18"/>
    </svg>
  </button>

  <%# Centre: page title %>
  <div class="ml-4 flex-1">
    <% if content_for?(:page_title) %>
      <h1 class="text-theme-sm font-semibold text-gray-800 dark:text-white">
        <%= yield :page_title %>
      </h1>
    <% end %>
  </div>

  <%# Right: user info + dark mode toggle %>
  <div class="flex items-center gap-3">

    <%# Dark/light toggle — Alpine reads/writes darkMode from parent x-data on <body> %>
    <button type="button"
            @click.prevent="darkMode = !darkMode; document.documentElement.classList.toggle('dark', darkMode); localStorage.setItem('darkMode', JSON.stringify(darkMode))"
            class="flex h-10 w-10 items-center justify-center rounded-lg border border-gray-200 text-gray-500
                   hover:bg-gray-100 hover:text-gray-700 dark:border-gray-800 dark:text-gray-400
                   dark:hover:bg-gray-800"
            aria-label="Toggle dark mode">
      <%# Sun icon — shown in dark mode %>
      <svg class="hidden dark:block" width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path fill-rule="evenodd" clip-rule="evenodd" d="M9.99998 1.5415C10.4142 1.5415 10.75 1.87729 10.75 2.2915V3.5415C10.75 3.95572 10.4142 4.2915 9.99998 4.2915C9.58577 4.2915 9.24998 3.95572 9.24998 3.5415V2.2915C9.24998 1.87729 9.58577 1.5415 9.99998 1.5415ZM10.0009 6.79327C8.22978 6.79327 6.79402 8.22904 6.79402 10.0001C6.79402 11.7712 8.22978 13.207 10.0009 13.207C11.772 13.207 13.2078 11.7712 13.2078 10.0001C13.2078 8.22904 11.772 6.79327 10.0009 6.79327ZM5.29402 10.0001C5.29402 7.40061 7.40135 5.29327 10.0009 5.29327C12.6004 5.29327 14.7078 7.40061 14.7078 10.0001C14.7078 12.5997 12.6004 14.707 10.0009 14.707C7.40135 14.707 5.29402 12.5997 5.29402 10.0001ZM15.9813 5.08035C16.2742 4.78746 16.2742 4.31258 15.9813 4.01969C15.6884 3.7268 15.2135 3.7268 14.9207 4.01969L14.0368 4.90357C13.7439 5.19647 13.7439 5.67134 14.0368 5.96423C14.3297 6.25713 14.8045 6.25713 15.0974 5.96423L15.9813 5.08035ZM18.4577 10.0001C18.4577 10.4143 18.1219 10.7501 17.7077 10.7501H16.4577C16.0435 10.7501 15.7077 10.4143 15.7077 10.0001C15.7077 9.58592 16.0435 9.25013 16.4577 9.25013H17.7077C18.1219 9.25013 18.4577 9.58592 18.4577 10.0001ZM14.9207 15.9806C15.2135 16.2735 15.6884 16.2735 15.9813 15.9806C16.2742 15.6877 16.2742 15.2128 15.9813 14.9199L15.0974 14.036C14.8045 13.7431 14.3297 13.7431 14.0368 14.036C13.7439 14.3289 13.7439 14.8038 14.0368 15.0967L14.9207 15.9806ZM9.99998 15.7088C10.4142 15.7088 10.75 16.0445 10.75 16.4588V17.7088C10.75 18.123 10.4142 18.4588 9.99998 18.4588C9.58577 18.4588 9.24998 18.123 9.24998 17.7088V16.4588C9.24998 16.0445 9.58577 15.7088 9.99998 15.7088ZM5.96356 15.0972C6.25646 14.8043 6.25646 14.3295 5.96356 14.0366C5.67067 13.7437 5.1958 13.7437 4.9029 14.0366L4.01902 14.9204C3.72613 15.2133 3.72613 15.6882 4.01902 15.9811C4.31191 16.274 4.78679 16.274 5.07968 15.9811L5.96356 15.0972ZM4.29224 10.0001C4.29224 10.4143 3.95645 10.7501 3.54224 10.7501H2.29224C1.87802 10.7501 1.54224 10.4143 1.54224 10.0001C1.54224 9.58592 1.87802 9.25013 2.29224 9.25013H3.54224C3.95645 9.25013 4.29224 9.58592 4.29224 10.0001ZM4.9029 5.9637C5.1958 6.25659 5.67067 6.25659 5.96356 5.9637C6.25646 5.6708 6.25646 5.19593 5.96356 4.90303L5.07968 4.01915C4.78679 3.72626 4.31191 3.72626 4.01902 4.01915C3.72613 4.31204 3.72613 4.78692 4.01902 5.07981L4.9029 5.9637Z" fill="currentColor"/>
      </svg>
      <%# Moon icon — shown in light mode %>
      <svg class="dark:hidden" width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M17.4571 11.7942C17.3004 11.7358 17.1237 11.7711 17.0025 11.8949C16.2429 12.6691 15.2138 13.1248 14.1143 13.1248C11.8187 13.1248 9.95463 11.2607 9.95463 8.96508C9.95463 7.56491 10.6731 6.28241 11.8671 5.54578C12.0007 5.46347 12.0742 5.31191 12.0567 5.15647C12.0392 5.00102 11.9336 4.86997 11.7851 4.81866C11.0773 4.57456 10.3384 4.45044 9.58374 4.45044C6.21706 4.45044 3.47925 7.18825 3.47925 10.555C3.47925 13.9217 6.21706 16.6595 9.58374 16.6595C12.3755 16.6595 14.8434 14.8115 15.5527 12.1407C15.5974 11.9765 15.5382 11.8017 15.4025 11.6976C15.2668 11.5934 15.082 11.5778 14.9299 11.6587L17.4571 11.7942Z" fill="currentColor"/>
      </svg>
    </button>

    <%# User info (desktop) %>
    <div class="hidden items-center gap-3 sm:flex">
      <span class="text-theme-sm text-gray-500 dark:text-gray-400"><%= current_user.email %></span>
      <span class="h-5 w-px bg-gray-200 dark:bg-gray-700"></span>
      <span class="badge badge-gray capitalize"><%= current_user.role.to_s.humanize %></span>
    </div>

  </div>

</header>
```

- [ ] **Step 2: Smoke-test the layout renders**

```bash
bundle exec rspec spec/requests/payments_spec.rb -e "returns 200" --format documentation
```

Expected: passes (layout changes don't affect request specs).

- [ ] **Step 3: Commit**

```bash
git add app/views/layouts/_header.html.erb
git commit -m "feat(MH-51): dark mode toggle button and header dark: chrome"
```

---

## Task 3: Auth pages dark mode (MH-51)

**Files:**
- Modify: `app/views/layouts/_auth_card.html.erb`

**Context:** The sign-in / password-reset pages use `_auth_card.html.erb` as their wrapper. The outer `div` uses `bg-gray-50` and the title uses `text-gray-900` — both need dark variants. The inner card uses the `card` utility which already includes `dark:border-gray-800 dark:bg-gray-900`. The brand name `MerchantHub` also needs `dark:text-white/90`.

- [ ] **Step 1: Update `_auth_card.html.erb`**

```erb
<%# Centred card wrapper for all unauthenticated Devise views.
    Usage: render "layouts/auth_card", title: "Sign in" do ... end %>
<div class="flex min-h-screen items-center justify-center bg-gray-50 px-4 py-12 dark:bg-gray-950">
  <div class="w-full max-w-md">
    <%# Brand mark %>
    <div class="mb-8 flex flex-col items-center gap-3">
      <div class="flex h-12 w-12 items-center justify-center rounded-xl bg-brand-500">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"
             class="h-7 w-7 text-white" aria-hidden="true">
          <path d="M4 4h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a2 2 0 0 1
                   2-2zm0 2v2h16V6H4zm0 4v8h16v-8H4zm2 2h4v2H6v-2z"/>
        </svg>
      </div>
      <span class="text-xl font-semibold text-gray-900 dark:text-white/90">MerchantHub</span>
    </div>
    <%# Card — uses `card` utility which already carries dark: variants %>
    <div class="card">
      <h1 class="mb-6 text-lg font-semibold text-gray-900 dark:text-white/90"><%= local_assigns[:title] %></h1>
      <%= yield %>
    </div>
  </div>
</div>
```

- [ ] **Step 2: Run session specs**

```bash
bundle exec rspec spec/requests/sessions_spec.rb --format documentation
```

Expected: all pass.

- [ ] **Step 3: Commit**

```bash
git add app/views/layouts/_auth_card.html.erb
git commit -m "feat(MH-51): auth card dark mode"
```

---

## Task 4: Payments table dark: audit (MH-51 + MH-47 prep)

**Files:**
- Modify: `app/views/payments/index.html.erb`

**Context:** The payments index uses many inline Tailwind classes without `dark:` variants. The `card` utility wrapping the whole table already has dark:, but everything inside needs updating. Map of changes needed:

| Element | Add |
|---------|-----|
| Page `<h1>` `text-gray-900` | `dark:text-white/90` |
| Page `<p>` `text-gray-500` | `dark:text-gray-400` |
| Toolbar border `border-gray-100` | `dark:border-gray-800` |
| Show N `<select>` (inline) | `dark:border-gray-700 dark:bg-gray-900 dark:text-white/90` |
| Caret span `text-gray-500` | `dark:text-gray-400` |
| "entries" span `text-gray-500` | `dark:text-gray-400` |
| Reference search `<input>` (inline) | `dark:border-gray-700 dark:bg-gray-900 dark:text-white/90 dark:placeholder:text-gray-500` |
| Search icon span `text-gray-400` | already fine |
| Filter toggle button (inline) | `dark:border-gray-700 dark:bg-gray-900 dark:text-gray-300 dark:hover:bg-gray-800` |
| Filter panel border `border-gray-100` | `dark:border-gray-800` |
| Filter checkbox labels `text-gray-700` | `dark:text-gray-300` |
| `<thead> <tr>` `border-gray-200 bg-gray-50` | `dark:border-gray-800 dark:bg-white/[0.03]` |
| `<th>` `text-gray-700` | `dark:text-gray-400` |
| `<tbody>` `divide-gray-100 bg-white` | `dark:divide-gray-800 dark:bg-transparent` |
| `<tr>` `hover:bg-gray-50` | `dark:hover:bg-white/[0.03]` |
| Payment ID `td` `text-gray-900` | `dark:text-white/90` |
| Shop ID `td` `text-gray-500` | `dark:text-gray-400` |
| Reference `td` `text-gray-700` | `dark:text-gray-300` |
| Amount `td` `text-gray-900` | `dark:text-white/90` |
| Date `td` `text-gray-500` | `dark:text-gray-400` |
| Pagination footer border `border-gray-100` | `dark:border-gray-800` |
| Pagination "showing" text `text-gray-500` | `dark:text-gray-400` |

- [ ] **Step 1: Rewrite `payments/index.html.erb` with all dark: classes**

```erb
<% content_for :title, t('.title') %>

<%# Page header %>
<div class="mb-6 flex items-center justify-between">
  <div>
    <h1 class="text-xl font-semibold text-gray-900 dark:text-white/90"><%= t('.title') %></h1>
    <p class="mt-0.5 text-theme-sm text-gray-500 dark:text-gray-400"><%= t('.subtitle') %></p>
  </div>
</div>

<%# Filter form — wraps the whole card. GET submission; Turbo Frame updates table only. %>
<%= form_with url: payments_path, method: :get,
      data: { controller: "filter", turbo_action: "advance" } do |f| %>

  <div class="card overflow-hidden p-0">

    <%# ── TailAdmin-style toolbar ──────────────────────────────────────────── %>
    <% active_panel_count = %i[status date_from date_to amount_min amount_max].count { |k| params[k].present? } %>
    <div class="flex flex-col gap-3 border-b border-gray-100 px-4 py-4 sm:flex-row sm:items-center sm:justify-between dark:border-gray-800">

      <%# Left: "Show N entries" select %>
      <div class="flex items-center gap-3">
        <span class="text-theme-sm text-gray-500 dark:text-gray-400"><%= t('.toolbar.show') %></span>
        <div class="relative">
          <%= f.select :per_page,
                options_for_select([[10, 10], [25, 25], [50, 50]], params.fetch(:per_page, 25).to_i),
                {},
                class: "h-9 appearance-none rounded-lg border border-gray-300 bg-white py-1.5 pr-8 pl-3 text-sm text-gray-800 shadow-theme-xs focus:border-brand-300 focus:ring-3 focus:ring-brand-500/10 focus:outline-hidden dark:border-gray-700 dark:bg-gray-900 dark:text-white/90",
                data: { action: "change->filter#submit" } %>
          <span class="pointer-events-none absolute top-1/2 right-2 -translate-y-1/2 text-gray-500 dark:text-gray-400">
            <svg class="stroke-current" width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
              <path d="M3.8335 5.9165L8.00016 10.0832L12.1668 5.9165" stroke="" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/>
            </svg>
          </span>
        </div>
        <span class="text-theme-sm text-gray-500 dark:text-gray-400"><%= t('.toolbar.entries') %></span>
      </div>

      <%# Right: reference search input + Filters toggle button %>
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center">

        <%# Reference search %>
        <div class="relative">
          <span class="pointer-events-none absolute top-1/2 left-4 -translate-y-1/2 text-gray-400 dark:text-gray-500">
            <svg class="fill-current" width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
              <path fill-rule="evenodd" clip-rule="evenodd" d="M3.04199 9.37363C3.04199 5.87693 5.87735 3.04199 9.37533 3.04199C12.8733 3.04199 15.7087 5.87693 15.7087 9.37363C15.7087 12.8703 12.8733 15.7053 9.37533 15.7053C5.87735 15.7053 3.04199 12.8703 3.04199 9.37363ZM9.37533 1.54199C5.04926 1.54199 1.54199 5.04817 1.54199 9.37363C1.54199 13.6991 5.04926 17.2053 9.37533 17.2053C11.2676 17.2053 13.0032 16.5344 14.3572 15.4176L17.1773 18.238C17.4702 18.5309 17.945 18.5309 18.2379 18.238C18.5308 17.9451 18.5309 17.4703 18.238 17.1773L15.4182 14.3573C16.5367 13.0033 17.2087 11.2669 17.2087 9.37363C17.2087 5.04817 13.7014 1.54199 9.37533 1.54199Z" fill=""/>
            </svg>
          </span>
          <%= f.text_field :reference,
                value: params[:reference],
                placeholder: t('.toolbar.search_placeholder'),
                class: "h-11 rounded-lg border border-gray-300 bg-white py-2.5 pr-4 pl-11 text-sm text-gray-800 placeholder:text-gray-400 shadow-theme-xs focus:border-brand-300 focus:ring-3 focus:ring-brand-500/10 focus:outline-hidden xl:w-[300px] dark:border-gray-700 dark:bg-gray-900 dark:text-white/90 dark:placeholder:text-gray-500",
                data: { action: "input->filter#submitDebounced" } %>
        </div>

        <%# Filters toggle button %>
        <button type="button"
                class="flex items-center justify-center gap-2 rounded-lg border border-gray-300 bg-white px-4 py-[9px] text-sm font-medium text-gray-700 shadow-theme-xs hover:bg-gray-50 sm:w-auto dark:border-gray-700 dark:bg-gray-900 dark:text-gray-300 dark:hover:bg-gray-800"
                data-action="click->filter#togglePanel"
                data-filter-target="panelToggle"
                aria-controls="filter-panel"
                aria-expanded="<%= active_panel_count > 0 ? 'true' : 'false' %>">
          <svg class="fill-current" width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
            <path fill-rule="evenodd" clip-rule="evenodd" d="M2.5 5.5C2.5 5.22386 2.72386 5 3 5H17C17.2761 5 17.5 5.22386 17.5 5.5C17.5 5.77614 17.2761 6 17 6H3C2.72386 6 2.5 5.77614 2.5 5.5ZM4.5 10C4.5 9.72386 4.72386 9.5 5 9.5H15C15.2761 9.5 15.5 9.72386 15.5 10C15.5 10.2761 15.2761 10.5 15 10.5H5C4.72386 10.5 4.5 10.2761 4.5 10ZM7 14.5C6.72386 14.5 6.5 14.7239 6.5 15C6.5 15.2761 6.72386 15.5 7 15.5H13C13.2761 15.5 13.5 15.2761 13.5 15C13.5 14.7239 13.2761 14.5 13 14.5H7Z" fill=""/>
          </svg>
          <%= t('.toolbar.filters') %>
          <% if active_panel_count > 0 %>
            <span class="inline-flex h-5 min-w-5 items-center justify-center rounded-full bg-brand-500 px-1 text-xs font-semibold text-white">
              <%= active_panel_count %>
            </span>
          <% end %>
        </button>

      </div>
    </div>
    <%# ── End toolbar ── %>

    <%# ── Collapsible filter panel ──────────────────────────────────────────── %>
    <% panel_open = active_panel_count > 0 %>
    <div id="filter-panel"
         data-filter-target="panel"
         class="<%= panel_open ? "" : "hidden" %> border-b border-gray-100 px-4 py-4 dark:border-gray-800">
      <div class="grid grid-cols-1 gap-x-6 gap-y-4 sm:grid-cols-2 lg:grid-cols-4">

        <%# Status multi-select checkboxes %>
        <fieldset>
          <legend class="form-label"><%= t('.filter.status_label') %></legend>
          <div class="mt-2 flex flex-wrap gap-x-4 gap-y-2">
            <% [["succeeded",  t('.filter.succeeded')],
                ["failed",     t('.filter.failed')],
                ["pending",    t('.filter.pending')],
                ["refunded",   t('.filter.refunded')],
                ["authorized", t('.filter.authorized')],
                ["voided",     t('.filter.voided')]].each do |value, label| %>
              <label class="inline-flex cursor-pointer items-center gap-1.5">
                <%= check_box_tag "status[]", value, Array(params[:status]).include?(value),
                      class: "h-4 w-4 rounded border-gray-300 accent-brand-500",
                      data: { action: "change->filter#submit" } %>
                <span class="text-theme-xs text-gray-700 dark:text-gray-300"><%= label %></span>
              </label>
            <% end %>
          </div>
        </fieldset>

        <%# Date range %>
        <div>
          <span class="form-label block"><%= t('.filter.date_range_label') %></span>
          <div class="mt-2 flex items-center gap-2">
            <%= f.date_field :date_from,
                  value: params[:date_from],
                  class: "form-input min-w-0 flex-1 py-2 text-sm",
                  data: { action: "change->filter#submit" } %>
            <span class="shrink-0 text-xs text-gray-400 dark:text-gray-600">–</span>
            <%= f.date_field :date_to,
                  value: params[:date_to],
                  class: "form-input min-w-0 flex-1 py-2 text-sm",
                  data: { action: "change->filter#submit" } %>
          </div>
        </div>

        <%# Amount range %>
        <div>
          <span class="form-label block"><%= t('.filter.amount_range_label') %></span>
          <div class="mt-2 flex items-center gap-2">
            <%= f.number_field :amount_min,
                  value: params[:amount_min],
                  step: "0.01", min: 0,
                  placeholder: t('.filter.amount_min_placeholder'),
                  class: "form-input min-w-0 flex-1 py-2 text-sm",
                  data: { action: "input->filter#submitDebounced" } %>
            <span class="shrink-0 text-xs text-gray-400 dark:text-gray-600">–</span>
            <%= f.number_field :amount_max,
                  value: params[:amount_max],
                  step: "0.01", min: 0,
                  placeholder: t('.filter.amount_max_placeholder'),
                  class: "form-input min-w-0 flex-1 py-2 text-sm",
                  data: { action: "input->filter#submitDebounced" } %>
          </div>
        </div>

        <%# Clear all filters %>
        <div class="flex items-end">
          <%= link_to t('.filter.clear_all'), payments_path(per_page: params[:per_page]),
                class: "btn btn-secondary text-sm",
                data: { turbo_frame: "payments-table", turbo_action: "advance" } %>
        </div>

      </div>
    </div>
    <%# ── End filter panel ── %>

    <%# ── Turbo Frame: chips + table + pagination ──────────────────────────── %>
    <turbo-frame id="payments-table">

      <%= render partial: "payments/filter_chips" %>

      <%# Table %>
      <div class="overflow-x-auto">
        <table class="min-w-full">
          <thead>
            <tr class="border-b border-gray-200 bg-gray-50 dark:border-gray-800 dark:bg-white/[0.03]">
              <%= sort_th t('.table.id'),        nil,           params %>
              <% if current_user.psp_role? %>
                <%= sort_th t('.table.shop'),    nil,           params %>
              <% end %>
              <%= sort_th t('.table.reference'), nil,           params %>
              <%= sort_th t('.table.amount'),    "amount",      params %>
              <%= sort_th t('.table.status'),    "status",      params %>
              <%= sort_th t('.table.created'),   "inserted_at", params %>
              <th class="px-4 py-3"><span class="sr-only"><%= t('.table.view') %></span></th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-100 bg-white dark:divide-gray-800 dark:bg-transparent">
            <% @payments.each do |payment| %>
              <tr class="hover:bg-gray-50 dark:hover:bg-white/[0.03]">
                <td class="border-r border-gray-100 px-4 py-3 font-mono text-theme-sm text-gray-900 dark:border-gray-800 dark:text-white/90">
                  <span class="block max-w-[10rem] truncate"><%= payment.id %></span>
                </td>
                <% if current_user.psp_role? %>
                  <td class="border-r border-gray-100 px-4 py-3 text-theme-sm text-gray-500 dark:border-gray-800 dark:text-gray-400">
                    <%= payment.shop_id %>
                  </td>
                <% end %>
                <td class="border-r border-gray-100 px-4 py-3 font-mono text-theme-sm text-gray-700 dark:border-gray-800 dark:text-gray-300">
                  <%= payment.merchant_reference.presence || "—" %>
                </td>
                <td class="border-r border-gray-100 px-4 py-3 text-theme-sm text-gray-900 whitespace-nowrap dark:border-gray-800 dark:text-white/90">
                  <%= number_to_currency(payment.amount / 100.0, unit: payment.currency + " ") %>
                </td>
                <td class="border-r border-gray-100 px-4 py-3 dark:border-gray-800">
                  <%= render partial: "payments/status_badge", locals: { status: payment.status } %>
                </td>
                <td class="border-r border-gray-100 px-4 py-3 text-theme-sm text-gray-500 whitespace-nowrap dark:border-gray-800 dark:text-gray-400">
                  <%= payment.inserted_at&.strftime("%d %b %Y %H:%M") %>
                </td>
                <td class="px-4 py-3 text-right">
                  <%= link_to t('.table.view'), payment_path(payment.id),
                        class: "table-action",
                        data: { turbo_frame: "payment-modal" } %>
                </td>
              </tr>
            <% end %>
            <% if @payments.empty? %>
              <tr>
                <td colspan="<%= current_user.psp_role? ? 7 : 6 %>"
                    class="px-4 py-10 text-center text-theme-sm text-gray-500 dark:text-gray-400">
                  <%= t('.table.empty') %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>

      <%# Pagination footer %>
      <% if @pagy.pages > 1 %>
        <div class="border-t border-gray-100 px-4 py-4 dark:border-gray-800">
          <div class="flex flex-col gap-3 xl:flex-row xl:items-center xl:justify-between">
            <p class="text-center text-theme-sm font-medium text-gray-500 xl:text-left dark:text-gray-400">
              <%= t('.pagination.showing', from: @pagy.from, to: @pagy.to, count: @pagy.count) %>
            </p>
            <%== @pagy.series_nav %>
          </div>
        </div>
      <% end %>

    </turbo-frame>
    <%# ── End Turbo Frame ── %>

  </div>
<% end %>
```

Note: `sort_th` is a helper defined in Task 6 (PaymentsHelper). To avoid a `NoMethodError` before Task 6 is done, add a temporary stub in `app/helpers/payments_helper.rb` now:

```ruby
# Temporary stub — replaced with full implementation in Task 6
def sort_th(label, _column, _params)
  content_tag(:th, label,
    class: "border-r border-gray-200 px-4 py-3 text-left text-theme-xs font-medium text-gray-700 dark:border-gray-800 dark:text-gray-400 last:border-r-0")
end
```

- [ ] **Step 2: Run payments request specs**

```bash
bundle exec rspec spec/requests/payments_spec.rb --format documentation
```

Expected: all pass.

- [ ] **Step 3: Commit**

```bash
git add app/views/payments/index.html.erb app/helpers/payments_helper.rb
git commit -m "feat(MH-51): payments table dark: audit and sort_th stub"
```

---

## Task 5: Pagy dark CSS + filter chips + modal dark (MH-51)

**Files:**
- Modify: `app/assets/tailwind/application.css`
- Modify: `app/views/payments/_filter_chips.html.erb`
- Modify: `app/views/payments/_modal_detail.html.erb`

**Context:**

**Pagy:** The `.pagy.series-nav` CSS block (currently at the bottom of `application.css`) has no dark variants. Prev/Next buttons need `dark:border-gray-700 dark:bg-gray-900 dark:text-gray-300 dark:hover:bg-gray-800`. Page number items need `dark:text-gray-300`. Current page needs `dark:text-brand-400`.

**Filter chips:** The chips container border `border-gray-100` needs `dark:border-gray-800`. The clear-all link `text-gray-500 hover:text-gray-700` needs `dark:text-gray-400 dark:hover:text-gray-300`.

**Modal detail:** Uses the `card` utility (already dark) but the `<dt>` and `<dd>` elements have inline `text-gray-500`/`text-gray-900` without dark variants.

- [ ] **Step 1: Update Pagy CSS in `application.css`**

Replace the entire `/* ─── Pagy pagination ─────── */` section with:

```css
/* ─── Pagy pagination — TailAdmin data table style ─────────────────────── */

.pagy.series-nav {
  @apply flex items-center gap-0.5;
}

/* Previous / Next — pill buttons (first & last child) */
.pagy.series-nav > a:first-child,
.pagy.series-nav > a:last-child {
  @apply shadow-theme-xs flex items-center justify-center rounded-lg border border-gray-300 bg-white
         px-3.5 py-2 text-theme-sm font-medium text-gray-700
         dark:border-gray-700 dark:bg-gray-900 dark:text-gray-300;
}
.pagy.series-nav > a:first-child { @apply mr-2; }
.pagy.series-nav > a:last-child  { @apply ml-2; }

.pagy.series-nav > a[href]:first-child:hover,
.pagy.series-nav > a[href]:last-child:hover  {
  @apply bg-gray-50 dark:bg-gray-800;
}

/* Disabled prev / next */
.pagy.series-nav > a[role="link"]:first-child,
.pagy.series-nav > a[role="link"]:last-child {
  @apply opacity-50 cursor-not-allowed text-gray-400 dark:text-gray-600;
}

/* Page number items */
.pagy.series-nav > a:not(:first-child):not(:last-child) {
  @apply flex h-9 w-9 items-center justify-center rounded-lg text-theme-sm font-medium text-gray-700
         dark:text-gray-300;
}

/* Inactive page hover */
.pagy.series-nav > a[href]:not(:first-child):not(:last-child):hover {
  @apply bg-blue-500/[0.08] text-brand-500 dark:bg-blue-500/[0.15] dark:text-brand-400;
}

/* Current page */
.pagy.series-nav > a[aria-current] {
  @apply bg-blue-500/[0.08] text-brand-500 cursor-default dark:bg-blue-500/[0.15] dark:text-brand-400;
}

/* Gap */
.pagy.series-nav > a[role="separator"] {
  @apply text-gray-400 cursor-default dark:text-gray-600;
}
```

- [ ] **Step 2: Update `_filter_chips.html.erb`**

```erb
<%# Dismissible chips for each active filter.
    Rendered inside turbo-frame#payments-table so chips update with every filter change. %>
<% active_filters = {
     status:     Array(params[:status]).reject(&:blank?),
     date_from:  Array(params[:date_from]).reject(&:blank?),
     date_to:    Array(params[:date_to]).reject(&:blank?),
     reference:  Array(params[:reference]).reject(&:blank?),
     amount_min: Array(params[:amount_min]).reject(&:blank?),
     amount_max: Array(params[:amount_max]).reject(&:blank?)
   }.reject { |_k, v| v.empty? } %>

<% if active_filters.any? %>
  <div class="flex flex-wrap items-center gap-2 border-b border-gray-100 px-4 py-3 dark:border-gray-800">
    <% active_filters.each do |key, values| %>
      <% values.each do |value| %>
        <%= link_to filter_chip_remove_path(key, value),
              class: "inline-flex items-center gap-1.5 rounded-full bg-blue-500/[0.08] px-3 py-1 text-xs font-medium text-brand-600 transition-colors hover:bg-blue-500/[0.12] dark:bg-blue-500/[0.15] dark:text-brand-400",
              data: { turbo_frame: "payments-table", turbo_action: "advance" } do %>
          <%= filter_chip_label(key, value) %>
          <svg class="h-3 w-3 shrink-0" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
            <path d="M6.28 5.22a.75.75 0 0 0-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 1 0 1.06 1.06L10 11.06l3.72 3.72a.75.75 0 1 0 1.06-1.06L11.06 10l3.72-3.72a.75.75 0 0 0-1.06-1.06L10 8.94 6.28 5.22Z"/>
          </svg>
        <% end %>
      <% end %>
    <% end %>
    <%= link_to t("payments.index.filter.clear_all", default: "Clear all"), payments_path(per_page: params[:per_page]),
          class: "ml-1 text-xs font-medium text-gray-500 underline hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-300",
          data: { turbo_frame: "payments-table", turbo_action: "advance" } %>
  </div>
<% end %>
```

- [ ] **Step 3: Update `_modal_detail.html.erb`**

Add dark variants to every `dt` and `dd` text colour. The card wrapper uses the `card` utility so the card background/border are already handled.

```erb
<%# app/views/payments/_modal_detail.html.erb %>
<%# Full-screen backdrop + centred card. Rendered inside <turbo-frame id="payment-modal">. %>
<div class="fixed inset-0 z-[9999] flex items-center justify-center px-4"
     data-controller="modal"
     data-action="keydown.esc@window->modal#close">

  <%# Backdrop %>
  <div class="absolute inset-0 bg-gray-900/60"
       data-action="click->modal#close"
       aria-hidden="true"></div>

  <%# Modal card %>
  <div class="relative w-full max-w-lg"
       data-action="click->modal#close:stop">
    <div class="card">

      <%# Header %>
      <div class="mb-4 flex items-start justify-between gap-4">
        <div>
          <p class="text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400"><%= t('.label') %></p>
          <p class="mt-0.5 font-mono text-theme-sm text-gray-900 break-all dark:text-white/90"><%= payment.id %></p>
        </div>
        <div class="flex items-center gap-3 shrink-0">
          <%= render partial: "payments/status_badge", locals: { status: payment.status } %>
          <button type="button"
                  class="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
                  data-action="click->modal#close"
                  aria-label="<%= t('.close') %>">
            <svg class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
              <path d="M6.28 5.22a.75.75 0 0 0-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 1 0 1.06 1.06L10 11.06l3.72 3.72a.75.75 0 1 0 1.06-1.06L11.06 10l3.72-3.72a.75.75 0 0 0-1.06-1.06L10 8.94 6.28 5.22Z"/>
            </svg>
          </button>
        </div>
      </div>

      <%# Detail fields %>
      <dl class="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <div>
          <dt class="text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400"><%= t('.fields.amount') %></dt>
          <dd class="mt-1 text-lg font-semibold text-gray-900 dark:text-white/90">
            <%= number_to_currency(payment.amount / 100.0, unit: payment.currency + " ") %>
          </dd>
        </div>

        <div>
          <dt class="text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400"><%= t('.fields.shop') %></dt>
          <dd class="mt-1 text-theme-sm font-mono text-gray-900 dark:text-white/90"><%= payment.shop_id %></dd>
        </div>

        <% if payment.merchant_reference.present? %>
          <div>
            <dt class="text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400"><%= t('.fields.reference') %></dt>
            <dd class="mt-1 text-theme-sm font-mono text-gray-900 dark:text-white/90"><%= payment.merchant_reference %></dd>
          </div>
        <% end %>

        <div>
          <dt class="text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400"><%= t('.fields.created') %></dt>
          <dd class="mt-1 text-theme-sm text-gray-900 dark:text-white/90">
            <%= payment.inserted_at&.strftime("%d %b %Y at %H:%M UTC") %>
          </dd>
        </div>

        <% if payment.idempotency_key.present? %>
          <div class="sm:col-span-2">
            <dt class="text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400"><%= t('.fields.idempotency_key') %></dt>
            <dd class="mt-1 text-theme-sm font-mono text-gray-900 break-all dark:text-white/90"><%= payment.idempotency_key %></dd>
          </div>
        <% end %>
      </dl>

    </div>
  </div>
</div>
```

- [ ] **Step 4: Run full suite**

```bash
bundle exec rspec spec/requests/ --format progress
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add app/assets/tailwind/application.css app/views/payments/_filter_chips.html.erb app/views/payments/_modal_detail.html.erb
git commit -m "feat(MH-51): pagy dark CSS, filter chips dark:, modal dark:"
```

---

## Task 6: Sortable columns — controller + helper + view (MH-47)

**Files:**
- Modify: `app/controllers/payments_controller.rb`
- Modify: `app/helpers/payments_helper.rb`
- Modify: `app/views/payments/index.html.erb` (replace stub `sort_th`)
- Modify: `spec/requests/payments_spec.rb`

**Context:** Sort is server-side via `?sort=amount&direction=asc` URL params. An allowlist (`SORTABLE_COLUMNS`) prevents arbitrary column injection. Sort state is preserved through filter params. Unsortable columns (ID, Shop, Reference, View) render a plain `<th>` without a sort link. The sort indicator shows two small triangles from `data-table-03.html` — the active direction triangle is highlighted (`fill-brand-500`) while the inactive is muted (`fill-gray-300 dark:fill-gray-700`).

- [ ] **Step 1: Write failing sort specs**

Add to `spec/requests/payments_spec.rb`, inside the existing `describe "GET /payments"` block after the existing filter specs:

```ruby
describe "sort" do
  let_it_be(:cheap)     { create(:tessera_payment, shop_id: "shop_abc", amount: 100,    inserted_at: 3.days.ago, updated_at: 3.days.ago) }
  let_it_be(:expensive) { create(:tessera_payment, shop_id: "shop_abc", amount: 99_900, inserted_at: 1.day.ago,  updated_at: 1.day.ago) }

  before { sign_in merchant_admin }

  it "sorts by amount ascending" do
    get payments_path(sort: "amount", direction: "asc")
    expect(response).to have_http_status(:ok)
    expect(response.body.index(cheap.id)).to be < response.body.index(expensive.id)
  end

  it "sorts by amount descending" do
    get payments_path(sort: "amount", direction: "desc")
    expect(response).to have_http_status(:ok)
    expect(response.body.index(expensive.id)).to be < response.body.index(cheap.id)
  end

  it "ignores unknown sort columns and falls back to inserted_at desc" do
    get payments_path(sort: "DROP TABLE users;", direction: "asc")
    expect(response).to have_http_status(:ok)
    # recent payment appears before older one (default inserted_at desc)
    expect(response.body.index(expensive.id)).to be < response.body.index(cheap.id)
  end

  it "ignores unknown direction and falls back to desc" do
    get payments_path(sort: "amount", direction: "INVALID")
    expect(response).to have_http_status(:ok)
  end
end
```

- [ ] **Step 2: Run to confirm they fail**

```bash
bundle exec rspec spec/requests/payments_spec.rb -e "sort" --format documentation
```

Expected: 4 failures (`sort` method not defined, ordering not applied correctly).

- [ ] **Step 3: Update `payments_controller.rb`**

```ruby
class PaymentsController < ApplicationController
  before_action :set_payment, only: %i[show refund void]

  ALLOWED_PER_PAGE   = [ 10, 25, 50 ].freeze
  SORTABLE_COLUMNS   = %w[amount inserted_at status].freeze
  SORT_DIRECTIONS    = %w[asc desc].freeze
  private_constant :ALLOWED_PER_PAGE, :SORTABLE_COLUMNS, :SORT_DIRECTIONS

  def index
    scope = policy_scope(Tessera::Payment, policy_scope_class: PaymentPolicy::Scope)
    scope = apply_filters(scope)
    scope = apply_sort(scope)
    @pagy, @payments = pagy(:offset, scope, limit: per_page_value)
    authorize Tessera::Payment, :index?, policy_class: PaymentPolicy
  end

  def show
    authorize @payment, :show?, policy_class: PaymentPolicy
  end

  def refund
    authorize @payment, :refund?, policy_class: PaymentPolicy
    client.post_refund(
      shop_id:    @payment.shop_id,
      payment_id: @payment.id,
      amount:     params[:amount].to_i,
      currency:   @payment.currency
    )
    redirect_to payment_path(@payment.id), notice: "Refund submitted successfully."
  rescue TesseraCoreClient::Error => e
    redirect_to payment_path(@payment.id), alert: "Refund failed: #{e.message}"
  end

  def void
    authorize @payment, :void?, policy_class: PaymentPolicy
    client.post_void(shop_id: @payment.shop_id, payment_id: @payment.id)
    redirect_to payment_path(@payment.id), notice: "Payment voided successfully."
  rescue TesseraCoreClient::Error => e
    redirect_to payment_path(@payment.id), alert: "Void failed: #{e.message}"
  end

  private

  def apply_filters(scope)
    scope = scope.with_statuses(params[:status])        if params[:status].present?
    if params[:date_from].present?
      begin
        scope = scope.from_date(params[:date_from])
      rescue ArgumentError, Date::Error
        # ignore malformed date — filter not applied
      end
    end
    if params[:date_to].present?
      begin
        scope = scope.to_date(params[:date_to])
      rescue ArgumentError, Date::Error
        # ignore malformed date — filter not applied
      end
    end
    scope = scope.with_reference(params[:reference])    if params[:reference].present?
    if params[:amount_min].present?
      scope = scope.amount_at_least((params[:amount_min].to_f * 100).round)
    end
    if params[:amount_max].present?
      scope = scope.amount_at_most((params[:amount_max].to_f * 100).round)
    end
    scope
  end

  # Applies URL-param-driven sort. Falls back to inserted_at desc for unknown/missing params.
  # SORTABLE_COLUMNS allowlist prevents SQL injection.
  def apply_sort(scope)
    col = SORTABLE_COLUMNS.include?(params[:sort]) ? params[:sort] : "inserted_at"
    dir = SORT_DIRECTIONS.include?(params[:direction]) ? params[:direction].to_sym : :desc
    scope.order(col => dir)
  end

  def per_page_value
    requested = params[:per_page].to_i
    ALLOWED_PER_PAGE.include?(requested) ? requested : 25
  end

  def set_payment
    @payment = Tessera::Payment.find(params[:id])
  end

  def client
    @client ||= TesseraCoreClient.new
  end
end
```

- [ ] **Step 4: Run sort specs — expect pass**

```bash
bundle exec rspec spec/requests/payments_spec.rb -e "sort" --format documentation
```

Expected: 4 passing.

- [ ] **Step 5: Replace stub `sort_th` helper with full implementation**

In `app/helpers/payments_helper.rb`, replace the stub `sort_th` method with:

```ruby
# Renders a sortable <th> cell.
# column: the param key (e.g. "amount") or nil for unsortable columns.
# current_params: request params hash, used to build the sort URL preserving other filters.
#
# Sortable columns show up/down triangle indicators (from TailAdmin data-table-03.html).
# The active direction triangle is highlighted (fill-brand-500); inactive is muted.
def sort_th(label, column, current_params)
  base_class = "px-4 py-3 text-left text-theme-xs font-medium text-gray-700 dark:text-gray-400 border-r border-gray-200 dark:border-gray-800 last:border-r-0"

  unless column
    return content_tag(:th, label, class: base_class)
  end

  active       = current_params[:sort] == column
  current_dir  = current_params[:direction] || "desc"
  next_dir     = (active && current_dir == "asc") ? "desc" : "asc"
  sort_params  = current_params.except("sort", "direction", "page").merge(sort: column, direction: next_dir)
  url          = payments_path(sort_params)

  up_class   = (active && current_dir == "asc")  ? "fill-brand-500" : "fill-gray-300 dark:fill-gray-700"
  down_class = (active && current_dir == "desc") ? "fill-brand-500" : "fill-gray-300 dark:fill-gray-700"

  content_tag(:th, class: base_class) do
    link_to url, class: "flex items-center gap-2 hover:text-gray-900 dark:hover:text-white",
                 data: { turbo_frame: "payments-table", turbo_action: "advance" } do
      concat(label)
      concat(content_tag(:span, class: "flex flex-col gap-0.5") do
        # Up triangle
        concat(content_tag(:svg, class: up_class, width: "8", height: "5", viewBox: "0 0 8 5",
                            fill: "none", xmlns: "http://www.w3.org/2000/svg") do
          content_tag(:path,
            d: "M4.40962 0.585167C4.21057 0.300808 3.78943 0.300807 3.59038 0.585166L1.05071 4.21327C0.81874 4.54466 1.05582 5 1.46033 5H6.53967C6.94418 5 7.18126 4.54466 6.94929 4.21327L4.40962 0.585167Z",
            fill: "")
        end)
        # Down triangle
        concat(content_tag(:svg, class: down_class, width: "8", height: "5", viewBox: "0 0 8 5",
                            fill: "none", xmlns: "http://www.w3.org/2000/svg") do
          content_tag(:path,
            d: "M4.40962 4.41483C4.21057 4.69919 3.78943 4.69919 3.59038 4.41483L1.05071 0.786732C0.81874 0.455343 1.05582 0 1.46033 0H6.53967C6.94418 0 7.18126 0.455342 6.94929 0.786731L4.40962 4.41483Z",
            fill: "")
        end)
      end)
    end
  end
end
```

Also remove the stub method if it still exists (there should only be one `sort_th` definition).

- [ ] **Step 6: Run full payments spec**

```bash
bundle exec rspec spec/requests/payments_spec.rb --format documentation
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/payments_controller.rb app/helpers/payments_helper.rb app/views/payments/index.html.erb spec/requests/payments_spec.rb
git commit -m "feat(MH-47): server-side sortable columns with sort_th helper and request specs"
```

---

## Task 7: Full suite verification + PR

**Files:**
- No code changes — verification only.

- [ ] **Step 1: Run full test suite**

```bash
bundle exec rspec --format progress
```

Expected: all green. If any failures, fix them before proceeding.

- [ ] **Step 2: Verify Tailwind build has no errors**

```bash
bundle exec rails tailwindcss:build 2>&1 | tail -5
```

Expected: exits 0, no errors.

- [ ] **Step 3: Check for i18n issues**

```bash
bundle exec i18n-tasks missing 2>&1 | head -20
bundle exec i18n-tasks unused 2>&1 | head -20
```

Expected: no new missing keys (we didn't add any new i18n keys). Unused warnings are pre-existing and suppressed by `config/i18n-tasks.yml`.

- [ ] **Step 4: Create PR**

```bash
git push -u origin HEAD
gh pr create \
  --title "feat: dark mode toggle + payments table dark audit + sortable columns (MH-47, MH-51)" \
  --body "$(cat <<'EOF'
## Summary

- **MH-51 Dark mode**: FOCT prevention inline script, Alpine `darkMode` state on body, sun/moon toggle in header, full `dark:` class audit across payments table, filter panel, chips, modal, auth card, and Pagy CSS
- **MH-47 Data table**: Server-side sortable columns (amount, status, inserted_at) with URL params `sort`/`direction`, TailAdmin triangle sort indicators, security allowlist in controller

## Test plan
- [ ] Toggle button in header switches theme, persists on hard refresh
- [ ] No flash of wrong theme (check light mode persists on reload)
- [ ] Payments table, filter panel, modal all look correct in both modes
- [ ] Sort by Amount asc/desc reorders rows correctly
- [ ] Filter chips and sort state coexist (sort preserved when filtering)
- [ ] Full RSpec suite green
EOF
)"
```
