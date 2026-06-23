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
    try {
      const response = await fetch(panel.dataset.tabSrc, {
        headers: { "Accept": "text/html" }
      })
      if (response.ok) {
        const html = await response.text()
        const content = panel.querySelector("[id$='-tab-content']")
        if (content) {
          content.innerHTML = html
        } else {
          panel.innerHTML = html
        }
      }
    } catch (e) {
      // Silently fail — stale content is better than an error
    }
  }

  #validTab(name) {
    return this.tabTargets.some(tab => tab.dataset.tab === name)
  }
}
