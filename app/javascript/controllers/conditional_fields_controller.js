import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dependent", "source"]
  static values = { showWhen: String }

  connect() {
    this.toggle()
  }

  toggle() {
    const selected = this.sourceTargets.find((field) => field.checked)?.value
    const visible = selected === this.showWhenValue

    this.dependentTargets.forEach((container) => {
      container.hidden = !visible
      container.querySelectorAll("input, select, textarea").forEach((field) => {
        field.disabled = !visible
      })
    })
  }
}
