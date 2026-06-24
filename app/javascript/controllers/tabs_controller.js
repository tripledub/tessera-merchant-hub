import { Controller } from "@hotwired/stimulus"

// Tabs with underline and icon — based on tailadmin tab-03 pattern.
// Manages active tab state, URL hash persistence, and panel visibility.
// Panels with data-tab-src fetch fresh content on each activation.
export default class extends Controller {
  static targets = ["tab", "panel"]
  static values = { default: { type: String, default: "overview" } }

  connect() {
    const hash = window.location.hash.replace("#", "")
    const initial = this.#validTab(hash) ? hash : this.defaultValue
    this.#activate(initial)
  }

  select(event) {
    event.preventDefault()
    const tab = event.currentTarget.dataset.tab
    this.#activate(tab)
    window.history.replaceState(null, "", `#${tab}`)
  }

  #activate(name) {
    this.tabTargets.forEach(tab => {
      const active = tab.dataset.tab === name
      tab.classList.toggle("text-brand-500", active)
      tab.classList.toggle("border-brand-500", active)
      tab.classList.toggle("dark:text-brand-400", active)
      tab.classList.toggle("dark:border-brand-400", active)
      tab.classList.toggle("text-gray-500", !active)
      tab.classList.toggle("border-transparent", !active)
    })

    this.panelTargets.forEach(panel => {
      const isActive = panel.dataset.tab === name
      panel.hidden = !isActive

      if (isActive && panel.dataset.tabSrc) {
        this.#fetchContent(panel)
      }
    })
  }

  async #fetchContent(panel) {
    const content = panel.querySelector("[id$='-tab-content']") || panel
    content.innerHTML = this.#spinnerHTML

    try {
      const response = await fetch(panel.dataset.tabSrc, {
        headers: { "Accept": "text/html" }
      })
      if (response.ok) {
        content.innerHTML = await response.text()
      } else {
        content.innerHTML = this.#errorHTML
      }
    } catch (e) {
      content.innerHTML = this.#errorHTML
    }
  }

  get #spinnerHTML() {
    return `<div class="flex items-center justify-center py-12">
      <svg class="h-6 w-6 animate-spin text-brand-500" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
      </svg>
    </div>`
  }

  get #errorHTML() {
    return `<div class="py-8 text-center text-sm text-gray-500 dark:text-gray-400">Failed to load. Click the tab to retry.</div>`
  }

  #validTab(name) {
    return this.tabTargets.some(tab => tab.dataset.tab === name)
  }
}
