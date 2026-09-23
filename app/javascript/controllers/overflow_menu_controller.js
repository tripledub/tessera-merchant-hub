import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "menu"]

  connect() {
    document.addEventListener("click", this.boundClickOutside = (event) => {
      if (!this.element.contains(event.target)) this.close()
    })
    document.addEventListener("keydown", this.boundEscape = (event) => {
      if (event.key === "Escape") this.close()
    })
  }

  disconnect() {
    document.removeEventListener("click", this.boundClickOutside)
    document.removeEventListener("keydown", this.boundEscape)
  }

  toggle(event) {
    event.stopPropagation()
    this.menuTarget.classList.toggle("hidden")
  }

  close() {
    this.menuTarget.classList.add("hidden")
  }
}
