import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"

const FRAGMENT_IDS = [
  "onboarding_progress",
  "onboarding_quick_replies",
  "onboarding_upload_slot",
  "onboarding_document_checklist",
  "onboarding_document_status_notices"
]
const AT_BOTTOM_TOLERANCE = 24

export default class extends Controller {
  static targets = ["composer", "input", "messages", "quickReplies", "quickReply", "submit", "typing", "uploadButton", "uploadInput", "uploadStatus"]
  static values  = { sessionId: String, token: String, uploadingTemplate: String }

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

    this.pendingApplicantMessageEl = this.appendApplicantPreview(message)
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
      this.showQuickReplies()
      this.inputTarget.focus()
    }
    // On success: stay disabled and keep typing indicator until WS complete event arrives
  }

  resizeInput() {
    if (!this.hasInputTarget) return

    this.inputTarget.style.height = "auto"
    this.inputTarget.style.height = `${Math.min(this.inputTarget.scrollHeight, 128)}px`
  }

  // A country chip sends exactly what typing it would: fill the textarea and
  // submit the composer, so the pending bubble, typing dots and streaming are
  // the ordinary ones.
  sendQuickReply(event) {
    if (this.inputTarget.disabled) return

    this.inputTarget.value = event.currentTarget.dataset.reply
    this.hideQuickReplies()
    this.composerTarget.requestSubmit()
  }

  // "Other" sends nothing: the applicant types their own answer.
  focusComposer() {
    this.inputTarget.focus()
    this.scrollComposerIntoView()
  }

  hideQuickReplies() {
    if (this.hasQuickRepliesTarget) this.quickRepliesTarget.hidden = true
  }

  showQuickReplies() {
    if (this.hasQuickRepliesTarget) this.quickRepliesTarget.hidden = false
  }

  triggerUpload() {
    if (this.hasUploadInputTarget) this.uploadInputTarget.click()
  }

  submitUpload(event) {
    if (event.target.files.length === 0) return

    const names = Array.from(event.target.files).map(file => file.name).join(", ")
    if (this.hasUploadStatusTarget) {
      const text = this.uploadingTemplateValue.replace("%{names}", names)
      this.uploadStatusTarget.innerHTML = `<p role="status" class="text-xs text-kyn-slate">${this.escapeHtml(text)}</p>`
    }

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
        this.finalizeStreamingBubble(data.bot_message)
        break
      case "error":
        this.handleStreamError()
        break
      case "document_update":
        this.appendBotMessage(data.bot_message)
        this.refreshFragments()
        break
    }
  }

  // A fixed assistant message pushed by the server (the outcome of an upload).
  appendBotMessage(html) {
    const wrapper = this.createStreamingBubble()
    wrapper.querySelector("[data-streaming-text]").innerHTML = html
    this.messagesTarget.append(wrapper)
    this.scrollToLatest()
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

  finalizeStreamingBubble(botMessage) {
    if (this.drainingTokens) {
      // Wait for the rAF drain to finish before finalizing
      requestAnimationFrame(() => this.finalizeStreamingBubble(botMessage))
      return
    }

    if (this.streamingBubble) {
      const bubble = this.streamingBubble.querySelector("[data-streaming-text]")
      if (bubble && botMessage) bubble.innerHTML = botMessage
    } else {
      // No tokens were streamed (fast response); create bubble with final message
      this.hideTyping()
      const wrapper = this.createStreamingBubble()
      const bubble = wrapper.querySelector("[data-streaming-text]")
      if (bubble && botMessage) bubble.innerHTML = botMessage
      this.streamingBubble = wrapper
      this.messagesTarget.append(wrapper)
    }

    this.streamingBubble = null
    const statusEl = this.pendingApplicantMessageEl?.querySelector("p")
    if (statusEl) statusEl.textContent = this.formatTimestamp(new Date())
    this.pendingApplicantMessageEl?.removeAttribute("id")
    this.pendingApplicantMessageEl = null
    this.setSubmitting(false)
    this.scrollToLatest()
    this.scrollComposerIntoView()
    this.inputTarget.focus({ preventScroll: true })

    this.refreshFragments()
  }

  handleStreamError() {
    this.streamingBubble?.remove()
    this.streamingBubble = null
    const statusEl = this.pendingApplicantMessageEl?.querySelector("p")
    if (statusEl) statusEl.textContent = "Failed to send — please try again"
    this.pendingApplicantMessageEl?.removeAttribute("id")
    this.pendingApplicantMessageEl = null
    this.hideTyping()
    this.setSubmitting(false)
    this.showQuickReplies()
    this.inputTarget.focus()
  }

  createStreamingBubble() {
    const wrapper = document.createElement("div")
    wrapper.className = "flex justify-start"

    const column = document.createElement("div")
    column.className = "max-w-[85%] sm:max-w-[75%]"

    const bubble = document.createElement("div")
    bubble.className = "kyn-bubble kyn-bubble-assistant chat-prose"
    bubble.setAttribute("data-streaming-text", "")

    column.append(bubble)
    wrapper.append(column)
    return wrapper
  }

  // What the server renders from the session state: the progress bar, the
  // quick-reply chips and Yes/No buttons, the upload button, the documents
  // checklist and the status notices. After each completed reply fetch the page
  // again and swap in the fresh fragments. (The composer's textarea is never
  // swapped, so what the applicant is typing is kept.)
  async refreshFragments() {
    try {
      const response = await fetch(window.location.href, {
        headers: { Accept: "text/html" },
        credentials: "same-origin"
      })
      if (!response.ok) return

      const doc = new DOMParser().parseFromString(await response.text(), "text/html")
      const wasAtBottom = this.isAtBottom()
      for (const id of FRAGMENT_IDS) {
        const fresh = doc.getElementById(id)
        if (fresh) document.getElementById(id)?.replaceWith(fresh)
      }
      // The swaps change how much room the messages have; an applicant who was
      // reading the latest message still sees all of it, one who scrolled up is left alone.
      if (wasAtBottom) this.scrollToLatest()
    } catch (_error) {
      // Leave what is on screen; the next reply or a reload corrects it.
    }
  }

  isAtBottom() {
    const list = this.messagesTarget
    return list.scrollHeight - list.scrollTop - list.clientHeight <= AT_BOTTOM_TOLERANCE
  }

  appendApplicantPreview(content) {
    const wrapper = document.createElement("div")
    wrapper.id = "onboarding_pending_applicant_message"
    wrapper.className = "flex justify-end"

    const column = document.createElement("div")
    column.className = "max-w-[85%] sm:max-w-[75%]"

    const bubble = document.createElement("div")
    bubble.className = "kyn-bubble kyn-bubble-applicant"
    bubble.textContent = content

    const status = document.createElement("p")
    status.className = "mt-1 px-1 text-right text-xs text-kyn-slate"
    status.textContent = "Sending"

    column.append(bubble, status)
    wrapper.append(column)
    this.messagesTarget.append(wrapper)
    return wrapper
  }

  setSubmitting(submitting) {
    this.inputTarget.disabled = submitting
    if (this.hasSubmitTarget) this.submitTarget.disabled = submitting
    this.quickReplyTargets.forEach(chip => { chip.disabled = submitting })
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

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
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
