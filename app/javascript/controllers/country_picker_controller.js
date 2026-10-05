import { Controller } from "@hotwired/stimulus"

// Searchable multi-select with removable pills, layered over a native
// <select multiple>. The select stays the source of truth (and the no-JS
// fallback); this controller hides it and keeps it in sync.
export default class extends Controller {
  static targets = ["select", "ui", "control", "pills", "input", "list"]
  static values = { removeLabel: String, noResults: String }

  connect() {
    this.options = Array.from(this.selectTarget.options).map((option) => ({
      value: option.value,
      label: option.text,
      key: this.fold(option.text)
    }))
    this.activeIndex = -1
    this.selectTarget.hidden = true
    this.uiTarget.hidden = false
    this.outsideClick = (event) => { if (!this.element.contains(event.target)) this.close() }
    this.focusLeft = (event) => { if (!this.element.contains(event.relatedTarget)) this.close() }
    document.addEventListener("click", this.outsideClick)
    this.element.addEventListener("focusout", this.focusLeft)
    this.renderPills()
    this.renderList()
  }

  disconnect() {
    document.removeEventListener("click", this.outsideClick)
    this.element.removeEventListener("focusout", this.focusLeft)
  }

  focusInput() {
    this.inputTarget.focus()
  }

  open() {
    if (this.suppressOpen) {
      this.suppressOpen = false
      return
    }
    this.listTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    this.listTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
    this.activeIndex = -1
  }

  filter() {
    this.open()
    this.activeIndex = -1
    this.renderList()
  }

  keydown(event) {
    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.open()
        this.moveActive(1)
        break
      case "ArrowUp":
        event.preventDefault()
        this.open()
        this.moveActive(-1)
        break
      case "Enter":
        // Never submit the form from the search box.
        event.preventDefault()
        if (this.activeIndex >= 0) this.toggleValue(this.visibleOptions()[this.activeIndex].value)
        break
      case "Escape":
        if (!this.listTarget.hidden) {
          event.preventDefault()
          this.close()
        }
        break
      case "Backspace":
        if (this.inputTarget.value === "") this.removeLast()
        break
    }
  }

  toggle(event) {
    event.preventDefault()
    this.toggleValue(event.currentTarget.dataset.value)
    this.inputTarget.focus()
  }

  remove(event) {
    event.preventDefault()
    event.stopPropagation()
    this.setSelected(event.currentTarget.dataset.value, false)
    this.sync()
    this.close()
    // Refocus without reopening the list, so it never covers the form controls below.
    this.suppressOpen = document.activeElement !== this.inputTarget
    this.inputTarget.focus()
  }

  // -- internals --

  visibleOptions() {
    const query = this.fold(this.inputTarget.value.trim())
    return query === "" ? this.options : this.options.filter((option) => option.key.includes(query))
  }

  // Lower-case and strip accents so "reunion" finds "Réunion".
  fold(text) {
    return text.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
  }

  selectedValues() {
    return new Set(Array.from(this.selectTarget.selectedOptions).map((option) => option.value))
  }

  toggleValue(value) {
    this.setSelected(value, !this.selectedValues().has(value))
    this.inputTarget.value = ""
    this.activeIndex = -1
    this.sync()
  }

  setSelected(value, selected) {
    const option = Array.from(this.selectTarget.options).find((candidate) => candidate.value === value)
    if (option) option.selected = selected
  }

  removeLast() {
    const selected = this.options.filter((option) => this.selectedValues().has(option.value))
    const last = selected[selected.length - 1]
    if (last) {
      this.setSelected(last.value, false)
      this.sync()
    }
  }

  sync() {
    this.renderPills()
    this.renderList()
  }

  moveActive(step) {
    const count = this.visibleOptions().length
    if (count === 0) return
    this.activeIndex = (this.activeIndex + step + count) % count
    this.renderList()
    const active = this.listTarget.querySelector("[aria-current='true']")
    if (active) {
      this.inputTarget.setAttribute("aria-activedescendant", active.id)
      active.scrollIntoView({ block: "nearest" })
    }
  }

  renderPills() {
    const selected = this.selectedValues()
    this.pillsTarget.replaceChildren(
      ...this.options.filter((option) => selected.has(option.value)).map((option) => {
        const pill = document.createElement("span")
        pill.className = "inline-flex items-center gap-1.5 rounded-full bg-gray-100 py-1 pl-3 pr-2 text-theme-sm text-gray-800 dark:bg-white/[0.07] dark:text-white/90"
        pill.dataset.countryPill = option.value
        pill.append(option.label)

        const button = document.createElement("button")
        button.type = "button"
        button.dataset.value = option.value
        button.dataset.action = "country-picker#remove"
        button.className = "rounded-full text-gray-500 hover:text-gray-800 focus:outline-none focus:ring-2 focus:ring-brand-500/40 dark:text-gray-400 dark:hover:text-white"
        button.setAttribute("aria-label", `${this.removeLabelValue} ${option.label}`)
        button.textContent = "×"
        pill.append(button)
        return pill
      })
    )
  }

  renderList() {
    const selected = this.selectedValues()
    const visible = this.visibleOptions()

    if (visible.length === 0) {
      const empty = document.createElement("li")
      empty.className = "px-4 py-2 text-theme-sm text-gray-500 dark:text-gray-400"
      empty.textContent = this.noResultsValue
      this.listTarget.replaceChildren(empty)
      return
    }

    this.listTarget.replaceChildren(
      ...visible.map((option, index) => {
        const item = document.createElement("li")
        const isSelected = selected.has(option.value)
        item.id = `country-option-${option.value}`
        item.setAttribute("role", "option")
        item.setAttribute("aria-selected", String(isSelected))
        item.dataset.value = option.value
        item.dataset.action = "mousedown->country-picker#toggle"
        if (index === this.activeIndex) item.setAttribute("aria-current", "true")
        item.className = "flex cursor-pointer items-center justify-between px-4 py-2 text-theme-sm text-gray-800 hover:bg-gray-50 dark:text-white/90 dark:hover:bg-white/[0.05] " +
          (index === this.activeIndex ? "bg-gray-50 dark:bg-white/[0.05] " : "") +
          (isSelected ? "font-medium" : "")
        item.append(option.label)
        if (isSelected) {
          const check = document.createElement("span")
          check.setAttribute("aria-hidden", "true")
          check.className = "text-brand-500"
          check.textContent = "✓"
          item.append(check)
        }
        return item
      })
    )
  }
}
