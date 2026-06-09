import { Controller } from "@hotwired/stimulus"

// Toggles the `dark` class on <html> and persists the preference to localStorage.
// The FOCT script in <head> applies the initial state before paint; this controller
// only needs to handle user-initiated toggles.
export default class extends Controller {
  toggle() {
    const isDark = !document.documentElement.classList.contains("dark")
    document.documentElement.classList.toggle("dark", isDark)
    localStorage.setItem("darkMode", JSON.stringify(isDark))
  }
}
