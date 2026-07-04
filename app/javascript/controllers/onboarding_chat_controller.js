import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["composer", "input", "messages", "submit", "typing", "uploadButton", "uploadInput"]
  static values  = { sessionId: String, token: String }

  connect() {
    this.scrollToLatest()
    this.resizeInput()

    this.observer = new MutationObserver(() => this.scrollToLatest())
    this.observer.observe(this.messagesTarget, { childList: true })

    this.streamingBubble = null
    this.tokenQueue = []
    this.drainingTokens = false

    if (this.hasSessionIdValue) {
      cable.getConsumer().then(consumer => {
        this.subscription = consumer.subscriptions.create(
          { channel: "OnboardingChannel", session_id: this.sessionIdValue, token: this.tokenValue },
          { received: (data) => this.handleCableData(data) }
        )
      })
    }
  }

  disconnect() {
    this.observer?.disconnect()
    this.subscription?.unsubscribe()
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
    if (!event.detail.success) {
      this.setSubmitting(false)
      this.hideTyping()
      this.inputTarget.focus()
    }
    // On success: stay disabled and keep typing indicator until WS complete event arrives
  }

  resizeInput() {
    if (!this.hasInputTarget) return

    this.inputTarget.style.height = "auto"
    this.inputTarget.style.height = `${Math.min(this.inputTarget.scrollHeight, 128)}px`
  }

  submitUpload(event) {
    if (event.target.files.length === 0) return

    event.target.form.requestSubmit()
  }

  uploadStart() {
    if (this.hasUploadButtonTarget) this.uploadButtonTarget.classList.add("opacity-50", "pointer-events-none")
  }

  uploadEnd() {
    if (this.hasUploadButtonTarget) this.uploadButtonTarget.classList.remove("opacity-50", "pointer-events-none")
    if (this.hasUploadInputTarget) this.uploadInputTarget.value = ""

    this.scrollComposerIntoView()
  }

  handleCableData(data) {
    switch (data.type) {
      case "token":
        this.appendStreamToken(data.content)
        break
      case "complete":
        this.finalizeStreamingBubble(data.bot_message, data.stage_changed)
        break
      case "error":
        this.handleStreamError()
        break
    }
  }

  appendStreamToken(token) {
    if (!this.streamingBubble) {
      this.hideTyping()
      this.streamingBubble = this.createStreamingBubble()
      this.messagesTarget.append(this.streamingBubble)
    }

    this.tokenQueue.push(token)

    if (!this.drainingTokens) {
      this.drainingTokens = true
      requestAnimationFrame(() => this.drainTokenQueue())
    }
  }

  drainTokenQueue() {
    const bubble = this.streamingBubble?.querySelector("[data-streaming-text]")
    if (bubble && this.tokenQueue.length > 0) {
      bubble.textContent += this.tokenQueue.shift()
      this.scrollToLatest()
    }

    if (this.tokenQueue.length > 0) {
      requestAnimationFrame(() => this.drainTokenQueue())
    } else {
      this.drainingTokens = false
    }
  }

  finalizeStreamingBubble(botMessage, stageChanged) {
    if (this.drainingTokens) {
      // Wait for the rAF drain to finish before finalizing
      requestAnimationFrame(() => this.finalizeStreamingBubble(botMessage, stageChanged))
      return
    }

    if (this.streamingBubble) {
      const bubble = this.streamingBubble.querySelector("[data-streaming-text]")
      if (bubble && botMessage) bubble.textContent = botMessage
    } else {
      // No tokens were streamed (fast response); create bubble with final message
      this.hideTyping()
      const wrapper = this.createStreamingBubble()
      const bubble = wrapper.querySelector("[data-streaming-text]")
      if (bubble && botMessage) bubble.textContent = botMessage
      this.streamingBubble = wrapper
      this.messagesTarget.append(wrapper)
    }

    this.streamingBubble = null
    const statusEl = document.getElementById("onboarding_pending_applicant_message")?.querySelector("p")
    if (statusEl) statusEl.textContent = this.formatTimestamp(new Date())
    this.setSubmitting(false)
    this.scrollToLatest()
    this.scrollComposerIntoView()
    this.inputTarget.focus({ preventScroll: true })

    if (stageChanged) this.refreshProgress()
  }

  handleStreamError() {
    this.streamingBubble?.remove()
    this.streamingBubble = null
    this.hideTyping()
    this.setSubmitting(false)
    this.inputTarget.focus()
  }

  createStreamingBubble() {
    const wrapper = document.createElement("div")
    wrapper.className = "flex"

    const row = document.createElement("div")
    row.className = "flex max-w-[85%] items-end gap-3 sm:max-w-[72%]"

    const avatar = document.createElement("div")
    avatar.className = "flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-gray-100 text-xs font-semibold text-gray-500 dark:bg-gray-800 dark:text-gray-300"
    avatar.textContent = "AI"

    const bubble = document.createElement("div")
    bubble.className = "rounded-2xl rounded-bl-sm bg-gray-100 px-4 py-3 text-sm leading-6 text-gray-800 dark:bg-gray-800 dark:text-gray-100"
    bubble.setAttribute("data-streaming-text", "")

    row.append(avatar, bubble)
    wrapper.append(row)
    return wrapper
  }

  refreshProgress() {
    const progressEl = document.querySelector("[data-onboarding-progress]")
    if (progressEl) progressEl.src = window.location.href
  }

  appendApplicantPreview(content) {
    const wrapper = document.createElement("div")
    wrapper.id = "onboarding_pending_applicant_message"
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

  formatTimestamp(date) {
    const day = String(date.getDate()).padStart(2, "0")
    const month = date.toLocaleString("en", { month: "short" })
    const hh = String(date.getHours()).padStart(2, "0")
    const mm = String(date.getMinutes()).padStart(2, "0")
    return `${day} ${month} ${hh}:${mm}`
  }

  scrollComposerIntoView() {
    if (!this.hasComposerTarget) return

    requestAnimationFrame(() => {
      this.composerTarget.scrollIntoView({ block: "end" })
    })
  }
}
