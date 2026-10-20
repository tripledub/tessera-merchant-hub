# frozen_string_literal: true

require "rails_helper"

# MH-398: the onboarding chat's JavaScript — pending bubble, typing dots,
# streamed reply and the progress bar refresh. There were no chat system specs
# before this. The cable stream is simulated by calling the Stimulus
# controller's own handler with the payloads the server broadcasts.
RSpec.describe "Applicant onboarding chat", type: :system do
  let(:applicant_user) { create(:applicant_user) }
  let!(:onboarding_session) do
    create(:onboarding_session, applicant: applicant_user.applicant, current_stage: :company_info)
  end

  def sign_in_and_open_chat
    visit applicant_user_password_sign_in_path
    fill_in "applicant_user_email", with: applicant_user.email
    fill_in "applicant_user_password", with: applicant_user.password
    click_button "Sign in"
    visit portal_onboarding_path
    expect(page).to have_css("[data-controller='onboarding-chat']")
  end

  def chat_controller_call(script)
    page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector("[data-controller='onboarding-chat']")
        const controller = window.Stimulus.getControllerForElementAndIdentifier(el, "onboarding-chat")
        return #{script}
      })()
    JS
  end

  def computed(selector, property)
    page.evaluate_script("getComputedStyle(document.querySelector(#{selector.to_json})).#{property}")
  end

  it "shows the applicant's message as a pending bubble and the typing dots while waiting" do
    sign_in_and_open_chat

    fill_in "message", with: "Acme Trading Ltd"
    find("button[aria-label='Send message']").click

    expect(page).to have_css("#onboarding_pending_applicant_message .kyn-bubble-applicant", text: "Acme Trading Ltd")
    expect(page).to have_css("#onboarding_pending_applicant_message", text: "Sending")
    expect(page).to have_css("[data-onboarding-chat-target='typing'] .kyn-typing-dot", count: 3, visible: :visible)
  end

  it "builds streamed and server-rendered assistant bubbles from the same utilities" do
    create(:onboarding_message, onboarding_session: onboarding_session, role: :bot, content: "Hello there")
    sign_in_and_open_chat

    chat_controller_call(%(controller.handleCableData({ type: "complete", bot_message: "<p>Streamed hello</p>", stage_changed: false })))

    expect(page).to have_css(".kyn-bubble.kyn-bubble-assistant.chat-prose", text: "Streamed hello")
    classes = page.all(".kyn-bubble-assistant").map { |bubble| bubble[:class].split.sort }
    expect(classes.uniq.size).to eq(1)
    expect(classes.first).to include("kyn-bubble", "kyn-bubble-assistant", "chat-prose")
  end

  it "replaces the Sending label with a timestamp once the reply completes" do
    sign_in_and_open_chat

    fill_in "message", with: "Acme Trading Ltd"
    find("button[aria-label='Send message']").click
    expect(page).to have_css("#onboarding_pending_applicant_message", text: "Sending")

    chat_controller_call(%(controller.handleCableData({ type: "complete", bot_message: "<p>Thanks</p>", stage_changed: false })))

    expect(page).to have_no_text("Sending")
    expect(page).to have_css(".kyn-bubble-assistant", text: "Thanks")
    expect(page).to have_css("[data-onboarding-chat-target='typing'].hidden", visible: :all)
  end

  it "refreshes the progress bar when a streamed reply reports a stage change" do
    sign_in_and_open_chat
    expect(page).to have_css("#onboarding_progress", text: "0% completed")

    onboarding_session.update!(current_stage: :directors_ubos, completed_stages: %w[company_info])
    chat_controller_call(%(controller.handleCableData({ type: "complete", bot_message: "<p>On to directors.</p>", stage_changed: true })))

    expect(page).to have_css("#onboarding_progress", text: "17% completed")
    expect(page).to have_css("#onboarding_progress [role='progressbar'][aria-valuenow='17']")
  end

  it "refreshes the progress bar after every completed reply, not only on a stage change" do
    sign_in_and_open_chat

    onboarding_session.update!(completed_stages: %w[company_info])
    chat_controller_call(%(controller.handleCableData({ type: "complete", bot_message: "<p>Fine.</p>", stage_changed: false })))

    expect(page).to have_css(".kyn-bubble-assistant", text: "Fine.")
    expect(page).to have_css("#onboarding_progress", text: "17% completed")
  end

  it "wraps long unbroken words inside the bubble without horizontal overflow at phone width" do
    create(:onboarding_message, onboarding_session: onboarding_session, role: :applicant, content: "x" * 400)
    sign_in_and_open_chat
    page.driver.resize(390, 800)

    page.driver.refresh
    expect(page).to have_css(".kyn-bubble-applicant")

    overflow = page.evaluate_script(<<~JS)
      (() => {
        const bubble = document.querySelector(".kyn-bubble-applicant")
        const list = document.getElementById("onboarding_messages")
        return { bubble: bubble.scrollWidth - bubble.clientWidth, list: list.scrollWidth - list.clientWidth, page: document.documentElement.scrollWidth - window.innerWidth }
      })()
    JS
    expect(overflow.values.max).to be <= 0
  end

  # MH-399: country quick-reply chips.
  context "with the country question" do
    let(:all_but_country) do
      { "company_info" => { "company_name" => "Acme Widgets Ltd", "registration_number" => "12345678",
                            "company_type" => "limited_company", "registered_address" => "1 High Street, London" } }
    end

    before do
      onboarding_session.update!(stage_data: all_but_country)
      create(:onboarding_message, onboarding_session: onboarding_session, role: :bot,
        content: "Which country is the company registered in?")
    end

    def chip(label)
      find("#onboarding_quick_replies button", text: label, exact_text: true)
    end

    def sent_messages
      onboarding_session.reload.onboarding_messages.where(role: :applicant).pluck(:content)
    end

    it "shows the three countries, Other and the hint, each chip at least 44px tall" do
      sign_in_and_open_chat

      expect(page).to have_css("#onboarding_quick_replies button", count: 4)
      expect(page).to have_text("Or type your country below.")
      heights = page.evaluate_script(<<~JS)
        Array.from(document.querySelectorAll("#onboarding_quick_replies button")).map(b => b.getBoundingClientRect().height)
      JS
      expect(heights.min).to be >= 44
    end

    it "sends exactly the country's name, as if it had been typed, and hides the strip" do
      sign_in_and_open_chat

      chip("Malta").click

      expect(page).to have_css("#onboarding_pending_applicant_message .kyn-bubble-applicant", text: "Malta")
      expect(page).to have_css("[data-onboarding-chat-target='typing'] .kyn-typing-dot", count: 3, visible: :visible)
      expect(page).to have_no_css("#onboarding_quick_replies button", visible: :visible)
      expect(page).to have_field("message", disabled: true, with: "")
      # The same request a typed reply makes: the message endpoint, the plain text.
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job["arguments"] }.flatten).to include("Malta")
    end

    it "posts the same job arguments for a chip as for typing the same text" do
      sign_in_and_open_chat
      chip("Cyprus").click
      expect(page).to have_css("#onboarding_pending_applicant_message", text: "Cyprus")
      chip_args = ActiveJob::Base.queue_adapter.enqueued_jobs.last["arguments"]

      onboarding_session.onboarding_messages.where(role: :applicant).destroy_all
      visit portal_onboarding_path
      fill_in "message", with: "Cyprus"
      find("button[aria-label='Send message']").click
      expect(page).to have_css("#onboarding_pending_applicant_message", text: "Cyprus")

      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.last["arguments"]).to eq(chip_args)
    end

    it "focuses the composer for Other and sends nothing, leaving the chips in place" do
      sign_in_and_open_chat

      chip("Other").click

      expect(page.evaluate_script("document.activeElement.name")).to eq("message")
      expect(page).to have_no_css("#onboarding_pending_applicant_message")
      expect(page).to have_css("#onboarding_quick_replies button", count: 4)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
    end

    it "works from the keyboard" do
      sign_in_and_open_chat

      page.execute_script("document.querySelector('#onboarding_quick_replies button').focus()")
      page.driver.browser.keyboard.type(:enter)

      expect(page).to have_css("#onboarding_pending_applicant_message", text: "United Kingdom")
    end

    it "brings the strip back after the reply when the country is still missing" do
      sign_in_and_open_chat
      chip("Malta").click
      expect(page).to have_no_css("#onboarding_quick_replies button", visible: :visible)

      chat_controller_call(%(controller.handleCableData({ type: "complete", bot_message: "<p>Sorry, which country again?</p>" })))
      create(:onboarding_message, onboarding_session: onboarding_session, role: :bot, content: "Sorry, which country again?")
      chat_controller_call("controller.refreshFragments()")

      expect(page).to have_css("#onboarding_quick_replies button", count: 4)
    end

    it "removes the strip after the reply once the country has been captured" do
      sign_in_and_open_chat
      chip("Malta").click

      onboarding_session.update!(stage_data: all_but_country.deep_merge("company_info" => { "country_of_incorporation" => "Malta" }))
      create(:onboarding_message, onboarding_session: onboarding_session, role: :applicant, content: "Malta")
      create(:onboarding_message, onboarding_session: onboarding_session, role: :bot, content: "Thanks, that's everything.")
      chat_controller_call(%(controller.handleCableData({ type: "complete", bot_message: "<p>Thanks, that's everything.</p>" })))

      expect(page).to have_css(".kyn-bubble-assistant", text: "Thanks, that's everything.")
      expect(page).to have_css("#onboarding_quick_replies")
      expect(page).to have_no_css("#onboarding_quick_replies button")
    end
  end

  it "styles the bubbles and the send button from the Kynetic tokens" do
    create(:onboarding_message, onboarding_session: onboarding_session, role: :applicant, content: "Hi")
    create(:onboarding_message, onboarding_session: onboarding_session, role: :bot, content: "Hello")
    sign_in_and_open_chat

    expect(computed(".kyn-bubble-applicant", "backgroundColor")).to eq("rgb(79, 91, 245)")
    expect(computed(".kyn-bubble-applicant", "color")).to eq("rgb(255, 255, 255)")
    expect(computed(".kyn-bubble-assistant", "backgroundColor")).to eq("rgb(240, 243, 247)")
    expect(computed("button[aria-label='Send message']", "borderTopLeftRadius")).not_to eq("0px")
  end
end
