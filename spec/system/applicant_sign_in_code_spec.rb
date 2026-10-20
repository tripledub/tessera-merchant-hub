# frozen_string_literal: true

require "rails_helper"

# MH-405: the six-box code input and the screens around it, in a real browser.
# The simulated autofill and paste events carry the same payloads a phone's
# keyboard and clipboard do; a manual iOS and Android autofill check is still
# listed on the PR.
RSpec.describe "Applicant one-time code sign-in", type: :system do
  let(:applicant) { create(:applicant, name: "Acme Widgets Ltd") }
  let(:inviter) { create(:user, :psp_admin) }
  let(:email) { "invited@example.com" }
  let!(:token) { ApplicantInvitation.issue!(applicant: applicant, email: email, invited_by: inviter).second }

  before { allow(ApplicantSignInCode).to receive(:generate_code).and_return("123456") }

  def open_code_page
    visit portal_invitation_path(token)
    click_button "Continue"
    expect(page).to have_css("fieldset input[data-code-input-target='box']", count: 6)
  end

  def boxes
    all("fieldset input[data-code-input-target='box']")
  end

  def values
    page.evaluate_script("Array.from(document.querySelectorAll(\"[data-code-input-target='box']\")).map(b => b.value)")
  end

  def focused_index
    page.evaluate_script("Array.from(document.querySelectorAll(\"[data-code-input-target='box']\")).indexOf(document.activeElement)")
  end

  def verify_button
    find("button[type='submit']", text: "Verify and continue")
  end

  def paste(text)
    page.execute_script(<<~JS, text)
      const data = new DataTransfer()
      data.setData("text", arguments[0])
      document.querySelectorAll("[data-code-input-target='box']")[3]
        .dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }))
    JS
  end

  def type_code(digits)
    digits.each_char { |digit| page.driver.browser.keyboard.type(digit) }
  end

  it "starts with the first box focused and Verify disabled" do
    open_code_page

    expect(focused_index).to eq(0)
    expect(verify_button).to be_disabled
    expect(values).to eq(Array.new(6, ""))
  end

  it "fills and advances as digits are typed, and enables Verify only at six" do
    open_code_page

    type_code("12345")
    expect(values).to eq(%w[1 2 3 4 5] + [ "" ])
    expect(focused_index).to eq(5)
    expect(verify_button).to be_disabled

    type_code("6")
    expect(values).to eq(%w[1 2 3 4 5 6])
    expect(verify_button).not_to be_disabled
  end

  it "does not submit by itself on the sixth digit" do
    open_code_page
    type_code("123456")

    sleep 0.5
    expect(page).to have_css("fieldset input[data-code-input-target='box']", count: 6)
    expect(page).to have_current_path(portal_sign_in_code_path)
    expect(ApplicantSignInCode.last.attempts).to eq(0)
  end

  it "ignores anything that is not a digit" do
    open_code_page

    page.driver.browser.keyboard.type("a")
    page.driver.browser.keyboard.type("-")
    page.driver.browser.keyboard.type("7")

    expect(values).to eq([ "7", "", "", "", "", "" ])
  end

  it "clears with Backspace and, on an empty box, steps back and clears the one before" do
    open_code_page
    type_code("123")
    expect(focused_index).to eq(3)

    page.driver.browser.keyboard.type(:Backspace)
    expect(values).to eq([ "1", "2", "", "", "", "" ])
    expect(focused_index).to eq(2)

    page.driver.browser.keyboard.type(:Backspace)
    expect(values).to eq([ "1", "", "", "", "", "" ])
    expect(focused_index).to eq(1)
  end

  it "moves with the arrow keys, Home and End" do
    open_code_page

    page.driver.browser.keyboard.type(:right)
    page.driver.browser.keyboard.type(:right)
    expect(focused_index).to eq(2)

    page.driver.browser.keyboard.type(:left)
    expect(focused_index).to eq(1)

    page.driver.browser.keyboard.type(:end)
    expect(focused_index).to eq(5)

    page.driver.browser.keyboard.type(:home)
    expect(focused_index).to eq(0)
  end

  it "spreads a pasted code over the boxes, ignoring spaces and a hyphen, wherever it was pasted" do
    open_code_page

    paste("123 456")
    expect(values).to eq(%w[1 2 3 4 5 6])
    expect(verify_button).not_to be_disabled

    paste("987-654")
    expect(values).to eq(%w[9 8 7 6 5 4])
  end

  it "fills from the first box and focuses the next empty one after a short paste" do
    open_code_page

    paste("12 3")

    expect(values).to eq([ "1", "2", "3", "", "", "" ])
    expect(focused_index).to eq(3)
  end

  it "spreads an OS autofill that puts the whole code into the first box" do
    open_code_page

    page.execute_script(<<~JS)
      const first = document.querySelector("[data-code-input-target='box']")
      first.value = "123456"
      first.dispatchEvent(new Event("input", { bubbles: true }))
    JS

    expect(values).to eq(%w[1 2 3 4 5 6])
    expect(verify_button).not_to be_disabled
  end

  it "shows a wrong code in place: announced, boxes cleared and marked, focus back on the first box, no reload" do
    open_code_page
    page.execute_script("window.__stillHere = true")

    type_code("000000")
    verify_button.click

    expect(page).to have_css("[role='alert']", text: "That code isn't right. You have 4 attempts left.")
    expect(boxes.map { |box| box["aria-invalid"] }.uniq).to eq([ "true" ])
    expect(values).to eq(Array.new(6, ""))
    expect(focused_index).to eq(0)
    expect(verify_button).to be_disabled
    expect(page.evaluate_script("window.__stillHere")).to be(true)
  end

  it "clears the error state as soon as the person starts typing again" do
    open_code_page
    type_code("000000")
    verify_button.click
    expect(page).to have_css("[role='alert']")

    type_code("1")

    expect(page).to have_no_css("[role='alert']", visible: :visible)
    expect(boxes.map { |box| box["aria-invalid"] }.uniq).to eq([ "false" ])
  end

  it "signs in from the keyboard alone: type the code, Tab to Verify, Enter" do
    open_code_page

    type_code("123456")
    page.driver.browser.keyboard.type(:Enter)

    expect(page).to have_current_path(portal_root_path)
    expect(ApplicantUser.find_by!(email: email)).to be_confirmed
  end

  it "offers a new code once the wait is over, and says so politely" do
    open_code_page
    ApplicantSignInCode.last.update!(created_at: 29.seconds.ago)
    visit portal_sign_in_code_path

    expect(page).to have_text("Resend code in 0:0")
    expect(page).to have_no_button("Resend code")
    expect(page).to have_button("Resend code", wait: 4)
    expect(page).to have_css("[aria-live='polite']", text: "You can now ask for a new code.")
  end

  it "shows the resend button straight away when no wait is left" do
    open_code_page
    ApplicantSignInCode.last.update!(created_at: 2.minutes.ago)
    visit portal_sign_in_code_path

    expect(page).to have_button("Resend code")
    expect(page).to have_no_text("Resend code in")
  end

  it "walks from an expired code to a new one" do
    open_code_page
    ApplicantSignInCode.last.update!(created_at: 11.minutes.ago, expires_at: 1.minute.ago)
    visit portal_sign_in_code_path

    expect(page).to have_text("This code has expired")
    click_button "Send a new code"

    expect(page).to have_text("Check your email")
    expect(ApplicantSignInCode.where(email: email).count).to eq(2)
  end

  it "shows Too many attempts after five wrong codes" do
    open_code_page

    5.times do
      type_code("000000")
      verify_button.click
      expect(page).to have_css("[data-code-input-target='box']") unless page.has_text?("Too many attempts", wait: 0.2)
    end

    expect(page).to have_text("Too many attempts")
    expect(page).to have_button("Send a new code")
  end

  it "fits a 375px screen with no sideways scrolling, and the boxes keep their size" do
    page.driver.resize(375, 812)
    open_code_page

    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
    widths = page.evaluate_script("Array.from(document.querySelectorAll('[data-code-input-target=box]')).map(b => b.getBoundingClientRect().width)")
    expect(widths.min).to be >= 36
    expect(page.evaluate_script("document.querySelector('[data-code-input-target=box]').getBoundingClientRect().height")).to be >= 52
  end
end
