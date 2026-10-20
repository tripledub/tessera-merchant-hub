import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dependent", "source"]
  static values = { showWhen: String }

  connect() {
    this.toggle()
  }

  toggle() {
    const selected = this.sourceTargets.find((field) => field.checked)?.value ||
      this.sourceTargets.find((field) => field.matches("select, input:not([type='radio']):not([type='checkbox'])"))?.value
    const visible = this.showWhenValue.split(",").includes(selected)

    this.dependentTargets.forEach((container) => {
      container.hidden = !visible
      container.querySelectorAll("input, select, textarea").forEach((field) => {
        field.disabled = !visible
        if (field.hasAttribute("data-conditional-required")) field.required = visible
      })
    })
  }
}
