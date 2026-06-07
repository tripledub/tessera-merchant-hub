import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "mh_sidebar_collapsed"

// Manages the sidebar panel: mobile slide-in/out and desktop icon-only collapse.
//
// HTML contract:
//   <div data-controller="sidebar">
//     <aside data-sidebar-target="panel" class="-translate-x-full lg:static lg:translate-x-0 ...">
//     <div  data-sidebar-target="overlay" data-action="click->sidebar#close" class="hidden">
//   </div>
//
// Toggle button (works for both mobile and desktop):
//   <button data-action="click->sidebar#toggle">
//
// Collapsed state persists across page loads via localStorage.
export default class extends Controller {
  static targets = ["panel", "overlay"]

  connect() {
    if (this.#isDesktop && localStorage.getItem(STORAGE_KEY) === "true") {
      this.#applyCollapsed(true)
    }
  }

  // Single entry-point for the hamburger button.
  // On desktop: toggles icon-only collapse. On mobile: opens/closes the drawer.
  toggle() {
    if (this.#isDesktop) {
      const collapsed = !this.panelTarget.dataset.collapsed
      this.#applyCollapsed(collapsed)
      localStorage.setItem(STORAGE_KEY, String(collapsed))
    } else {
      this.panelTarget.classList.contains("translate-x-0")
        ? this.close()
        : this.#openMobile()
    }
  }

  // Called by clicking the overlay scrim or a close button inside the sidebar.
  close() {
    this.panelTarget.classList.remove("translate-x-0")
    this.panelTarget.classList.add("-translate-x-full")
    this.overlayTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  // ── Private ──────────────────────────────────────────────────────────────

  #openMobile() {
    this.panelTarget.classList.remove("-translate-x-full")
    this.panelTarget.classList.add("translate-x-0")
    this.overlayTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  #applyCollapsed(collapsed) {
    if (collapsed) {
      this.panelTarget.dataset.collapsed = ""
      this.panelTarget.classList.add("!w-[90px]")
    } else {
      delete this.panelTarget.dataset.collapsed
      this.panelTarget.classList.remove("!w-[90px]")
    }
  }

  get #isDesktop() {
    return window.matchMedia("(min-width: 1024px)").matches
  }
}
