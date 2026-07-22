// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import { Turbo } from "@hotwired/turbo-rails"
import "controllers"

// Override Turbo's confirm dialog with a styled modal.
// Any element using data-turbo-confirm will trigger this instead of window.confirm().
// If the triggering element also has data-confirm-required-text, the Confirm
// button stays disabled until the typed input matches that text exactly
// (used by the admin Applicant delete action — MH-170).
Turbo.config.forms.confirm = (message, _formElement, submitter) => {
  const modal = document.getElementById("confirm-modal")
  if (!modal) return Promise.resolve(confirm(message))

  const messageEl = document.getElementById("confirm-modal-message")
  const inputWrapper = document.getElementById("confirm-modal-input-wrapper")
  const input = document.getElementById("confirm-modal-input")
  const confirmBtn = document.getElementById("confirm-modal-confirm")
  const cancelBtn = document.getElementById("confirm-modal-cancel")

  messageEl.textContent = message

  // submitter is only populated when the triggering element is the actual
  // form submitter (e.g. button_to). A link_to with data-turbo-method builds
  // a synthetic form with no submitter, so data-confirm-required-text would
  // be silently ignored — always use button_to for anything that needs this gate.
  const requiredText = submitter?.dataset?.confirmRequiredText

  const setConfirmDisabled = (disabled) => {
    confirmBtn.disabled = disabled
    confirmBtn.classList.toggle("opacity-50", disabled)
    confirmBtn.classList.toggle("cursor-not-allowed", disabled)
  }

  if (requiredText) {
    inputWrapper.classList.remove("hidden")
    input.value = ""
    input.placeholder = requiredText
    setConfirmDisabled(true)
  } else {
    inputWrapper.classList.add("hidden")
    setConfirmDisabled(false)
  }

  modal.classList.remove("hidden")

  return new Promise((resolve) => {
    const onInput = () => setConfirmDisabled(input.value !== requiredText)

    const cleanup = () => {
      confirmBtn.removeEventListener("click", onConfirm)
      cancelBtn.removeEventListener("click", onCancel)
      modal.removeEventListener("click", onBackdrop)
      input.removeEventListener("input", onInput)
      modal.classList.add("hidden")
    }

    const onConfirm = () => {
      if (confirmBtn.disabled) return
      cleanup()
      resolve(true)
    }
    const onCancel = () => { cleanup(); resolve(false) }
    const onBackdrop = (e) => { if (e.target === modal) { cleanup(); resolve(false) } }

    if (requiredText) input.addEventListener("input", onInput)
    confirmBtn.addEventListener("click", onConfirm)
    cancelBtn.addEventListener("click", onCancel)
    modal.addEventListener("click", onBackdrop)
  })
}
