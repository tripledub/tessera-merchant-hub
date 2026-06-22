import { Controller } from "@hotwired/stimulus"

// Tabs with underline and icon — based on tailadmin tab-03 pattern.
// Manages active tab state, URL hash persistence, and panel visibility.
//
// Usage:
//   <div data-controller="tabs" data-tabs-default-value="overview">
//     <button data-tabs-target="tab" data-tab="overview" data-action="click->tabs#select">Overview</button>
//     <div data-tabs-target="panel" data-tab="overview">...</div>
//   </div>
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
      panel.hidden = panel.dataset.tab !== name
    })
  }

  #validTab(name) {
    return this.tabTargets.some(tab => tab.dataset.tab === name)
  }
}
