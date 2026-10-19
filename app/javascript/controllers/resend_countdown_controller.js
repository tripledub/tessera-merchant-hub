import { Controller } from "@hotwired/stimulus"

// MH-405: "Resend code in 0:30". The server says how many seconds are left (the
// code service enforces the real gap); the page counts down silently and says
// once, politely, when asking for a new code is possible again.
export default class extends Controller {
  static targets = ["waiting", "time", "action", "status"]
  static values = { seconds: Number, ready: String }

  connect() {
    this.deadline = Date.now() + this.secondsValue * 1000
    this.tick(false)
    if (this.remaining() > 0) this.timer = setInterval(() => this.tick(true), 1000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  remaining() {
    return Math.max(0, Math.ceil((this.deadline - Date.now()) / 1000))
  }

  tick(announce) {
    const left = this.remaining()
    if (left > 0) {
      this.timeTarget.textContent = `${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")}`
      return
    }

    clearInterval(this.timer)
    this.waitingTarget.hidden = true
    this.actionTarget.hidden = false
    if (announce) this.statusTarget.textContent = this.readyValue
  }
}
