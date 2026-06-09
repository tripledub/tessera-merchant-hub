# MH-37 Sidebar Navigation Design

**Goal:** Wire the Team and All Users links into the TailAdmin sidebar so users can navigate to them without knowing the URL.

**Architecture:** Two additions to `_sidebar.html.erb` — a Team link in the existing merchant section, and a new Admin group containing All Users in the PSP section. Two new icon partials. No controller, policy, or route changes required.

**Tech Stack:** Rails ERB, TailAdmin sidebar pattern, `nav_link_to` helper, SVG icon partials, existing i18n keys.

---

## Sidebar structure after change

### PSP users (`psp_role?`)

```
Menu
  Payments
  Shops
  Onboard          ← psp_admin only (existing)

Admin              ← new group label, psp_admin only
  All Users        ← new link → admin_users_path
```

### Merchant users (`merchant_role?`)

```
My Account
  Payments
  Shops
  Team             ← new link → team_index_path
```

---

## Files

### Modified
- `app/views/layouts/_sidebar.html.erb`
  - Add `nav_link_to t('layouts.navigation.team'), team_index_path, controller: "team", icon: :team` inside the `merchant_role?` block, after Shops
  - Add a new `psp_admin?`-gated block below the Menu group: group label "Admin" + `nav_link_to t('layouts.navigation.users'), admin_users_path, controller: "users", icon: :users`

### Created
- `app/views/shared/icons/_team.html.erb` — group/people SVG (TailAdmin style, `fill="currentColor"`)
- `app/views/shared/icons/_users.html.erb` — user-with-cog or shield-person SVG (distinct from Team to signal admin context)

### No changes needed
- `config/locales/en.yml` — `layouts.navigation.team` and `layouts.navigation.users` already exist
- `app/policies/user_policy.rb` — existing `admin_index?` gates access
- `config/routes.rb` — routes already defined
- `app/views/layouts/_navigation.html.erb` — legacy partial, not rendered; leave untouched

---

## Active state

`nav_link_to` uses `controller_name == controller` for the active highlight:
- `TeamController` → `controller_name` = `"team"` → matches `controller: "team"` ✓
- `Admin::UsersController` → `controller_name` = `"users"` → matches `controller: "users"` ✓

---

## i18n group label

The new "Admin" group label needs one new i18n key:

```yaml
layouts:
  navigation:
    admin: Admin   # new
```

---

## Testing

- Request spec: `GET /admin/users` redirects non-psp_admin users (existing coverage — verify still passes)
- Request spec: `GET /team` redirects non-merchant users (existing coverage — verify still passes)
- No new request specs needed — the sidebar is a layout partial and nav visibility is purely conditional on `current_user.role`; role-based access is already covered by existing specs
- Manual smoke: sign in as psp_admin → Admin section visible with All Users link active on that page; sign in as merchant_admin → Team link visible in My Account section

---

## Out of scope

- `_navigation.html.erb` legacy top nav partial — not rendered anywhere, no changes
- Collapsible sub-menus — YAGNI; two items don't warrant accordion complexity
- Merchants index link in sidebar — separate ticket
