import { Controller } from "@hotwired/stimulus"

// MH-405: six single-digit boxes for the one-time sign-in code.
//
// The boxes are real inputs and are never submitted themselves: the digits are
// assembled into one hidden field. Only the first box has autocomplete
// "one-time-code" and no length cap, so an OS autofill that puts the whole code
// into it is spread over the boxes. There is no auto-submit: each submit uses
// one of the code's five attempts, so the person presses Verify.
const LENGTH = 6

export default class extends Controller {
  static targets = ["box", "hidden", "submit", "error"]
  static values = { error: Boolean }

  connect() {
    this.digits = this.boxTargets.map((box) => box.value.replace(/\D/g, "").slice(0, 1))
    this.render()
    this.focusBox(0)

    this.onSubmitStart = () => { this.submitTarget.disabled = true }
    this.onSubmitEnd = () => this.render()
    this.element.addEventListener("turbo:submit-start", this.onSubmitStart)
    this.element.addEventListener("turbo:submit-end", this.onSubmitEnd)
  }

  disconnect() {
    this.element.removeEventListener("turbo:submit-start", this.onSubmitStart)
    this.element.removeEventListener("turbo:submit-end", this.onSubmitEnd)
  }

  input(event) {
    const index = this.boxTargets.indexOf(event.target)
    const typed = event.target.value.replace(/\D/g, "")
    const inserted = typeof event.data === "string" && event.data.length === 1 ? event.data : null

    if (inserted && /\d/.test(inserted)) return this.place(index, inserted)
    if (inserted) return this.render() // a letter or symbol: put the old digit back
    if (typed.length > 1) return this.fill(typed) // autofill, or a paste that arrived as input
    this.place(index, typed)
  }

  paste(event) {
    event.preventDefault()
    const digits = (event.clipboardData || window.clipboardData).getData("text").replace(/\D/g, "")
    if (digits) this.fill(digits)
  }

  keydown(event) {
    const index = this.boxTargets.indexOf(event.target)
    if (event.ctrlKey || event.metaKey || event.altKey) return

    switch (event.key) {
      case "Backspace":
        event.preventDefault()
        if (this.digits[index]) {
          this.digits[index] = ""
          this.changed()
        } else if (index > 0) {
          this.digits[index - 1] = ""
          this.changed()
          this.focusBox(index - 1)
        }
        break
      case "Delete":
        event.preventDefault()
        this.digits[index] = ""
        this.changed()
        break
      case "ArrowLeft": event.preventDefault(); this.focusBox(index - 1); break
      case "ArrowRight": event.preventDefault(); this.focusBox(index + 1); break
      case "Home": event.preventDefault(); this.focusBox(0); break
      case "End": event.preventDefault(); this.focusBox(LENGTH - 1); break
      default:
        // Printable keys other than digits do nothing.
        if (event.key.length === 1 && !/\d/.test(event.key)) event.preventDefault()
    }
  }

  select(event) {
    event.target.select()
  }

  place(index, digit) {
    this.digits[index] = digit
    this.changed()
    if (digit) this.focusBox(Math.min(index + 1, LENGTH - 1))
  }

  // Fills from the first box with up to six digits, then moves to the next empty one.
  fill(digits) {
    const chars = digits.slice(0, LENGTH).split("")
    this.digits = this.digits.map((_, i) => chars[i] || "")
    this.changed()
    const next = this.digits.findIndex((digit) => digit === "")
    this.focusBox(next === -1 ? LENGTH - 1 : next)
  }

  changed() {
    this.clearError()
    this.render()
  }

  render() {
    this.boxTargets.forEach((box, i) => { box.value = this.digits[i] })
    this.hiddenTarget.value = this.digits.join("")
    this.submitTarget.disabled = this.digits.join("").length !== LENGTH
  }

  clearError() {
    this.boxTargets.forEach((box) => box.setAttribute("aria-invalid", "false"))
    if (this.hasErrorTarget) this.errorTarget.hidden = true
  }

  focusBox(index) {
    const box = this.boxTargets[Math.max(0, Math.min(index, LENGTH - 1))]
    box.focus()
    box.select()
  }
}
