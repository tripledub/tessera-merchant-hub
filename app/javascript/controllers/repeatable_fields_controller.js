import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["add", "item", "template", "status"]
  static values = {
    addedMessage: String,
    min: { type: Number, default: 0 },
    max: { type: Number, default: 0 },
    removedMessage: String
  }

  connect() {
    this._nextKey = 0
    this.updateControls()
  }

  add() {
    if (this.maximumReached) return

    const key = `${Date.now()}_${this._nextKey++}`
    const fragment = this.templateTarget.content.cloneNode(true)

    fragment.querySelectorAll("*").forEach((element) => {
      Array.from(element.attributes).forEach((attribute) => {
        if (attribute.value.includes("NEW_RECORD")) {
          element.setAttribute(attribute.name, attribute.value.replaceAll("NEW_RECORD", key))
        }
      })
    })

    const item = fragment.querySelector("[data-repeatable-fields-target~='item']")
    this.templateTarget.before(fragment)
    this.updateControls()
    this.announce(this.addedMessageValue)
    this.focusFirstField(item)
    this.dispatch("added", { detail: { item } })
  }

  remove(event) {
    if (this.minimumReached) return

    const item = event.currentTarget.closest("[data-repeatable-fields-target~='item']")
    const destroyField = item?.querySelector("[data-repeatable-fields-target~='destroy']")
    if (!item) return

    if (destroyField?.dataset.persisted === "true") {
      destroyField.value = "1"
      item.hidden = true
    } else {
      item.remove()
    }

    this.updateControls()
    this.announce(this.removedMessageValue)
    this.dispatch("removed", { detail: { item } })
  }

  get visibleItems() {
    return this.itemTargets.filter((item) => !item.hidden)
  }

  get minimumReached() {
    return this.visibleItems.length <= this.minValue
  }

  get maximumReached() {
    return this.maxValue > 0 && this.visibleItems.length >= this.maxValue
  }

  updateControls() {
    if (this.hasAddTarget) this.setDisabled(this.addTarget, this.maximumReached)

    this.visibleItems.forEach((item) => {
      const remove = item.querySelector("[data-repeatable-fields-target~='remove']")
      if (remove) this.setDisabled(remove, this.minimumReached)
    })
  }

  setDisabled(button, disabled) {
    button.disabled = disabled
    button.setAttribute("aria-disabled", disabled.toString())
  }

  focusFirstField(item) {
    item?.querySelector("input:not([type='hidden']), select, textarea, button")?.focus()
  }

  announce(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }
}
