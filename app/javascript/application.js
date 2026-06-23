// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import { Turbo } from "@hotwired/turbo-rails"
import "controllers"

// Override Turbo's native browser confirm with a styled modal.
// Any element using data-turbo-confirm will trigger this instead of window.confirm().
Turbo.setConfirmMethod((message) => {
  const modal = document.getElementById("confirm-modal")
  if (!modal) return Promise.resolve(confirm(message))

  const messageEl = document.getElementById("confirm-modal-message")
  messageEl.textContent = message
  modal.classList.remove("hidden")

  return new Promise((resolve) => {
    const confirmBtn = document.getElementById("confirm-modal-confirm")
    const cancelBtn = document.getElementById("confirm-modal-cancel")

    const cleanup = () => {
      confirmBtn.removeEventListener("click", onConfirm)
      cancelBtn.removeEventListener("click", onCancel)
      modal.removeEventListener("click", onBackdrop)
      modal.classList.add("hidden")
    }

    const onConfirm = () => { cleanup(); resolve(true) }
    const onCancel = () => { cleanup(); resolve(false) }
    const onBackdrop = (e) => { if (e.target === modal) { cleanup(); resolve(false) } }

    confirmBtn.addEventListener("click", onConfirm)
    cancelBtn.addEventListener("click", onCancel)
    modal.addEventListener("click", onBackdrop)
  })
})
