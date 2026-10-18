# frozen_string_literal: true

require "rails_helper"

# Test-only page that renders every state of the applicant primitives (MH-395),
# mirroring how repeatable_fields_spec.rb mounts its preview. The route lives in
# config/routes.rb behind Rails.env.test?.
class KynComponentsPreviewController < ActionController::Base
  def show
    render inline: <<~ERB, layout: false
      <!doctype html>
      <html lang="en">
        <head>
          <%= stylesheet_link_tag "tailwind" %>
          <%= javascript_importmap_tags %>
        </head>
        <body class="bg-kyn-bg font-kynetic p-6">
          <section id="buttons" class="space-y-3">
            <button id="btn-primary" type="button" class="kyn-btn-primary">Primary</button>
            <button id="btn-primary-disabled" type="button" class="kyn-btn-primary" disabled>Primary disabled</button>
            <button id="btn-secondary" type="button" class="kyn-btn-secondary">Secondary</button>
            <button id="btn-secondary-disabled" type="button" class="kyn-btn-secondary" disabled>Secondary disabled</button>
            <a id="btn-link" href="#" class="kyn-btn-primary">Link styled as a button</a>
          </section>

          <section id="fields" class="space-y-4 mt-6">
            <div class="kyn-field">
              <label class="kyn-label" for="f-default">Default</label>
              <input id="f-default" type="text" class="kyn-input" placeholder="you@company.com">
            </div>
            <div class="kyn-field">
              <label class="kyn-label" for="f-error">Error</label>
              <input id="f-error" type="text" class="kyn-input" value="nope" aria-invalid="true" aria-describedby="f-error-message">
              <p id="f-error-message" class="form-error" data-form-validation-error>Enter a valid email address.</p>
            </div>
            <div class="kyn-field">
              <label class="kyn-label" for="f-disabled">Disabled</label>
              <input id="f-disabled" type="text" class="kyn-input" value="Locked" disabled>
            </div>
            <div class="kyn-field">
              <label class="kyn-label" for="f-select">Select</label>
              <select id="f-select" class="kyn-input"><option>One</option><option>Two</option></select>
            </div>
            <div class="kyn-field">
              <label class="kyn-label" for="f-textarea">Textarea</label>
              <textarea id="f-textarea" class="kyn-input" rows="4"></textarea>
            </div>
            <label class="kyn-check-label" id="check-off-label"><input id="check-off" type="checkbox" class="kyn-checkbox"> Unchecked</label>
            <label class="kyn-check-label" id="check-on-label"><input id="check-on" type="checkbox" class="kyn-checkbox" checked> Checked</label>
          </section>

          <section id="card" class="mt-6"><div id="card-box" class="kyn-card">Card</div></section>
          <p class="mt-6"><a id="link" href="#" class="kyn-link">A link</a></p>

          <form id="validation" class="mt-6 space-y-4" data-controller="form-validation" data-action="submit->form-validation#submitForm">
            <div class="kyn-field">
              <label class="kyn-label" for="v-name">Name</label>
              <input id="v-name" name="preview[name]" type="text" class="kyn-input" required>
            </div>
            <div>
              <label class="form-label" for="v-legacy">Legacy field</label>
              <input id="v-legacy" name="preview[legacy]" type="text" class="form-input" required>
            </div>
            <button id="submit" type="submit" class="kyn-btn-primary">Submit</button>
          </form>
        </body>
      </html>
    ERB
  end
end

RSpec.describe "Applicant UI primitives", type: :system do # rubocop:disable RSpec/DescribeClass
  def style(selector, property)
    page.evaluate_script("getComputedStyle(document.querySelector(#{selector.to_json})).#{property}")
  end

  # Colours transition over 150ms, so wait for the computed value to settle.
  def expect_style(selector, property, expected)
    page.document.synchronize do
      actual = style(selector, property)
      raise Capybara::ExpectationNotMet, "#{selector} #{property} is #{actual.inspect}, expected #{expected.inspect}" unless actual == expected
    end
  end

  def height(selector)
    page.evaluate_script("document.querySelector(#{selector.to_json}).getBoundingClientRect().height")
  end

  before { visit "/kyn-components-preview" }

  it "renders every state" do
    expect(page).to have_css("#buttons .kyn-btn-primary", count: 3)
    expect(page).to have_css("#buttons .kyn-btn-secondary", count: 2)
    expect(page).to have_css("#btn-primary-disabled:disabled")
    expect(page).to have_css("#btn-secondary-disabled:disabled")
    expect(page).to have_css("input.kyn-input#f-default")
    expect(page).to have_css("input.kyn-input[aria-invalid='true'] + p.form-error")
    expect(page).to have_css("input.kyn-input:disabled")
    expect(page).to have_css("select.kyn-input")
    expect(page).to have_css("textarea.kyn-input")
    expect(page).to have_css("input.kyn-checkbox:not(:checked)")
    expect(page).to have_css("input.kyn-checkbox:checked")
    expect(page).to have_css("#card-box.kyn-card")
    expect(page).to have_css("a.kyn-link")
  end

  it "makes every control at least 44px tall" do
    %w[#btn-primary #btn-secondary #btn-link #f-default #f-select #f-textarea #check-off-label].each do |selector|
      expect(height(selector)).to be >= 44, "#{selector} is #{height(selector)}px tall"
    end
  end

  it "uses the Figma token colours and radius" do
    expect_style("#btn-primary", "backgroundColor", "rgb(79, 91, 245)")
    expect_style("#btn-primary", "color", "rgb(255, 255, 255)")
    expect_style("#btn-primary", "borderTopLeftRadius", "12px")
    expect_style("#btn-primary-disabled", "backgroundColor", "rgb(167, 173, 250)")
    expect_style("#btn-secondary", "backgroundColor", "rgb(255, 255, 255)")
    expect_style("#btn-secondary", "borderTopColor", "rgb(226, 232, 240)")
    expect_style("#btn-secondary", "color", "rgb(14, 27, 43)")
    expect_style("#btn-secondary-disabled", "color", "rgb(91, 104, 120)")
    expect_style("#f-default", "borderTopColor", "rgb(226, 232, 240)")
    expect_style("#f-default", "borderTopLeftRadius", "12px")
    expect_style("#f-error", "borderTopColor", "rgb(201, 52, 43)")
    expect_style("#f-disabled", "backgroundColor", "rgb(247, 249, 252)")
    expect_style("#f-error-message", "color", "rgb(201, 52, 43)")
    expect_style("#card-box", "borderTopLeftRadius", "16px")
    expect_style("#link", "color", "rgb(63, 75, 216)")
  end

  it "darkens the primary button and tints the secondary button on hover, but not when disabled" do
    page.find("#btn-primary").hover
    expect_style("#btn-primary", "backgroundColor", "rgb(70, 80, 224)")

    page.find("#btn-secondary").hover
    expect_style("#btn-secondary", "backgroundColor", "rgb(247, 249, 252)")

    page.find("#btn-primary-disabled").hover
    expect_style("#btn-primary-disabled", "backgroundColor", "rgb(167, 173, 250)")
  end

  it "shows a focus ring when a control takes keyboard focus" do
    page.driver.browser.keyboard.type(:Tab)
    expect(page.evaluate_script("document.activeElement.id")).to eq("btn-primary")
    expect(style("#btn-primary", "boxShadow")).to include("3px")
    expect(style("#btn-primary", "boxShadow")).not_to eq("none")

    page.find("#f-default").click
    expect_style("#f-default", "borderTopColor", "rgb(79, 91, 245)")
    expect(style("#f-default", "boxShadow")).to include("3px")
  end

  it "fills a checked checkbox with the primary colour" do
    expect_style("#check-on", "backgroundColor", "rgb(79, 91, 245)")
    expect_style("#check-off", "backgroundColor", "rgb(255, 255, 255)")
  end

  describe "inline validation with the form-validation controller" do
    it "styles kyn-input errors from aria-invalid without adding the legacy error class" do
      click_button "Submit"

      name = page.find("#v-name")
      expect(name["aria-invalid"]).to eq("true")
      expect(name[:class]).to include("kyn-input")
      expect(name[:class]).not_to include("form-input-error")
      expect(name[:class]).not_to include("form-input")
      expect_style("#v-name", "borderTopColor", "rgb(201, 52, 43)")

      message = page.find("#v-name + p[data-form-validation-error]")
      expect(message).to have_text("Name is required")
      expect(name["aria-describedby"]).to eq(message[:id])
      expect_style("#v-name + p", "color", "rgb(201, 52, 43)")
    end

    it "clears the error when the field is corrected" do
      click_button "Submit"
      page.find("#v-name").fill_in(with: "Test Applicant")
      page.find("#v-legacy").click

      expect(page).to have_no_css("#v-name[aria-invalid]")
      expect(page).to have_no_css("#v-name + p[data-form-validation-error]")
      expect(page.find("#v-name")[:class]).to include("kyn-input")
    end

    it "still swaps the legacy classes on legacy markup" do
      click_button "Submit"

      expect(page.find("#v-legacy")[:class]).to include("form-input-error")
      expect(page.find("#v-legacy")[:class]).not_to match(/\bform-input\b(?!-)/)

      page.find("#v-legacy").fill_in(with: "ok")
      page.find("#v-name").click

      expect(page.find("#v-legacy")[:class]).to match(/\bform-input\b(?!-)/)
      expect(page.find("#v-legacy")[:class]).not_to include("form-input-error")
    end
  end
end
