import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"

const controllerSource = readFileSync(
  new URL("../../../app/javascript/controllers/modal_controller.js", import.meta.url),
  "utf8"
).replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")

const { default: ModalController } = await import(
  `data:text/javascript;base64,${Buffer.from(controllerSource).toString("base64")}`
)

function focusable({ disabled = false } = {}) {
  return {
    disabled,
    focus() {
      document.activeElement = this
    },
    getAttribute(name) {
      return name === "aria-hidden" ? null : null
    },
    hasAttribute() {
      return false
    }
  }
}

function modalController(elements) {
  const controller = new ModalController()
  controller.element = {
    contains(element) {
      return elements.includes(element)
    },
    querySelectorAll() {
      return elements
    }
  }
  return controller
}

test("wraps Tab from the last enabled control to the first", () => {
  global.document = { activeElement: null }
  const first = focusable()
  const disabled = focusable({ disabled: true })
  const last = focusable()
  const controller = modalController([ first, disabled, last ])
  const event = { preventDefaultCalled: false, preventDefault() { this.preventDefaultCalled = true }, shiftKey: false }

  document.activeElement = last
  controller.trapFocus(event)

  assert.equal(event.preventDefaultCalled, true)
  assert.equal(document.activeElement, first)
})

test("wraps Shift+Tab from the first enabled control to the last", () => {
  global.document = { activeElement: null }
  const first = focusable()
  const last = focusable()
  const controller = modalController([ first, last ])
  const event = { preventDefaultCalled: false, preventDefault() { this.preventDefaultCalled = true }, shiftKey: true }

  document.activeElement = first
  controller.trapFocus(event)

  assert.equal(event.preventDefaultCalled, true)
  assert.equal(document.activeElement, last)
})
