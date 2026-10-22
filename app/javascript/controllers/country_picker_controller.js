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
        pill.className = "inline-flex items-center gap-1.5 rounded-full bg-kyn-primary-tint py-1 pl-3 pr-2 text-[13px] font-semibold text-kyn-primary-text"
        pill.dataset.countryPill = option.value
        pill.append(option.label)

        const button = document.createElement("button")
        button.type = "button"
        button.dataset.value = option.value
        button.dataset.action = "country-picker#remove"
        button.className = "grid size-6 place-items-center rounded-full text-kyn-primary-text hover:bg-kyn-surface focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-kyn-primary/30"
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
      empty.className = "px-4 py-3 text-[14px] text-kyn-slate"
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
        item.className = "flex min-h-11 cursor-pointer items-center justify-between px-4 py-2.5 text-[15px] text-kyn-navy hover:bg-kyn-bg " +
          (index === this.activeIndex ? "bg-kyn-primary-tint " : "") +
          (isSelected ? "font-semibold" : "")
        item.append(option.label)
        if (isSelected) {
          const check = document.createElement("span")
          check.setAttribute("aria-hidden", "true")
          check.className = "text-kyn-primary"
          check.textContent = "✓"
          item.append(check)
        }
        return item
      })
    )
  }
}
