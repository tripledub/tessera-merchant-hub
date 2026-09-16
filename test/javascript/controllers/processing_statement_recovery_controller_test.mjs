import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"

const controllerSource = readFileSync(
  new URL("../../../app/javascript/controllers/processing_statement_recovery_controller.js", import.meta.url),
  "utf8"
).replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")

const { default: RecoveryController } = await import(
  `data:text/javascript;base64,${Buffer.from(controllerSource).toString("base64")}`
)

test("an error live update reveals admin recovery controls", () => {
  const controller = new RecoveryController()
  controller.statusTarget = { dataset: { status: "error" } }
  controller.hasMapTarget = true
  controller.mapTarget = { hidden: false }
  controller.hasRemapTarget = true
  controller.remapTarget = { hidden: true }
  controller.hasRemoveTarget = true
  controller.removeTarget = { hidden: true }

  controller.sync()

  assert.equal(controller.mapTarget.hidden, true)
  assert.equal(controller.remapTarget.hidden, false)
  assert.equal(controller.removeTarget.hidden, false)
})
