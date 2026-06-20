import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "form"]

  formTargetConnected(form) {
    this.syncValue()
  }

  selectTargetConnected() {
    this.selectTarget.addEventListener("change", () => this.syncValue())
  }

  syncValue() {
    const form = this.formTarget.closest("form") || this.formTarget.querySelector("form")
    if (!form) return

    let input = form.querySelector("input[name='document_type']")
    if (!input) {
      input = document.createElement("input")
      input.type = "hidden"
      input.name = "document_type"
      form.appendChild(input)
    }
    input.value = this.selectTarget.value
  }
}
