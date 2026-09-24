import { Controller } from "@hotwired/stimulus"

// MH-334: disables the submit button for the duration of a Turbo-driven
// form submission, so a rapid double-click (or a slow response re-clicked)
// can't fire the request twice. Listening on turbo:submit-start/-end rather
// than the button's own click avoids leaving the button stuck disabled if
// a data-turbo-confirm dialog on the click is cancelled — that never
// reaches submit-start at all, only an accepted confirmation does.
export default class extends Controller {
  static targets = ["button"]

  connect() {
    this.onSubmitStart = () => { if (this.hasButtonTarget) this.buttonTarget.disabled = true }
    this.onSubmitEnd = () => { if (this.hasButtonTarget) this.buttonTarget.disabled = false }
    this.element.addEventListener("turbo:submit-start", this.onSubmitStart)
    this.element.addEventListener("turbo:submit-end", this.onSubmitEnd)
  }

  disconnect() {
    this.element.removeEventListener("turbo:submit-start", this.onSubmitStart)
    this.element.removeEventListener("turbo:submit-end", this.onSubmitEnd)
  }
}
