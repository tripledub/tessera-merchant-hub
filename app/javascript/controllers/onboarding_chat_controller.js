import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["composer", "input", "messages", "submit", "typing"]

  connect() {
    this.scrollToLatest()
    this.resizeInput()

    this.observer = new MutationObserver(() => this.scrollToLatest())
    this.observer.observe(this.messagesTarget, { childList: true })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  submitOnEnter(event) {
    if (event.key !== "Enter" || event.shiftKey) return

    event.preventDefault()
    event.target.form.requestSubmit()
  }

  submitStart() {
    const message = this.inputTarget.value.trim()
    if (message.length === 0) return

    this.appendApplicantPreview(message)
    this.inputTarget.value = ""
    this.resizeInput()
    this.setSubmitting(true)
    this.showTyping()
    this.scrollToLatest()
    this.scrollComposerIntoView()
  }

  submitEnd(event) {
    this.setSubmitting(false)
    this.hideTyping()
    this.scrollToLatest()
    this.scrollComposerIntoView()

    if (!event.detail.success) {
      this.inputTarget.focus()
    } else {
      this.inputTarget.focus({ preventScroll: true })
    }
  }

  resizeInput() {
    if (!this.hasInputTarget) return

    this.inputTarget.style.height = "auto"
    this.inputTarget.style.height = `${Math.min(this.inputTarget.scrollHeight, 128)}px`
  }

  appendApplicantPreview(content) {
    const wrapper = document.createElement("div")
    wrapper.className = "flex justify-end"

    const row = document.createElement("div")
    row.className = "flex max-w-[85%] flex-row-reverse items-end gap-3 sm:max-w-[72%]"

    const avatar = document.createElement("div")
    avatar.className = "flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-brand-500 text-white"
    avatar.textContent = "You"

    const body = document.createElement("div")
    const bubble = document.createElement("div")
    bubble.className = "rounded-2xl rounded-br-sm bg-brand-500 px-4 py-3 text-sm leading-6 text-white"
    bubble.textContent = content

    const status = document.createElement("p")
    status.className = "mt-1 text-right text-xs text-gray-500 dark:text-gray-500"
    status.textContent = "Sending"

    body.append(bubble, status)
    row.append(avatar, body)
    wrapper.append(row)
    this.messagesTarget.append(wrapper)
  }

  setSubmitting(submitting) {
    this.inputTarget.disabled = submitting
    if (this.hasSubmitTarget) this.submitTarget.disabled = submitting
  }

  showTyping() {
    if (this.hasTypingTarget) this.typingTarget.classList.remove("hidden")
  }

  hideTyping() {
    if (this.hasTypingTarget) this.typingTarget.classList.add("hidden")
  }

  scrollToLatest() {
    requestAnimationFrame(() => {
      this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
    })
  }

  scrollComposerIntoView() {
    if (!this.hasComposerTarget) return

    requestAnimationFrame(() => {
      this.composerTarget.scrollIntoView({ block: "end" })
    })
  }
}
