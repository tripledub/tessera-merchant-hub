# frozen_string_literal: true

require "rails_helper"

# MH-420 / MH-421: what a reply changes on the server (the stage, the Yes/No
# buttons) reaches the open page without a reload. No ActionCable runs in the test
# environment, so each example changes the session on the server and then calls the
# chat controller's refresh, which is what the `complete` message triggers.
RSpec.describe "Chat: the open page follows the session", type: :system do
  let(:applicant) { create(:applicant, company_name: "Acme Widgets", registry_jurisdiction: "gb") }
  let!(:applicant_user) { create(:applicant_user, applicant: applicant) }
  let(:onboarding_session) do
    create(:onboarding_session, applicant: applicant, current_stage: :business_activity,
                                stage_data: { "company_info" => { "company_name" => "Acme Widgets" } })
  end
  let(:checklist) do
    [ { "category" => "corporate", "subject" => "company", "document_types" => %w[certificate_of_incorporation],
        "label" => "Certificate of incorporation", "deferred" => false } ]
  end

  def sign_in_and_open_chat
    visit applicant_user_password_sign_in_path
    fill_in "applicant_user_email", with: applicant_user.email
    fill_in "applicant_user_password", with: applicant_user.password
    click_button "Sign in"
    visit portal_onboarding_path
  end

  def refresh_chat
    page.execute_script(<<~JS)
      const element = document.querySelector("[data-controller~='onboarding-chat']")
      window.Stimulus.getControllerForElementAndIdentifier(element, "onboarding-chat").refreshFragments()
    JS
  end

  def move_to_documents_stage
    onboarding_session.update!(current_stage: :document_collection, document_checklist: checklist)
  end

  before do
    create(:onboarding_message, onboarding_session: onboarding_session, role: :bot, content: "What does the business do?")
  end

  describe "the documents stage (MH-420)" do
    it "shows the upload button and the checklist when the stage moves on while the page is open" do
      sign_in_and_open_chat
      expect(page).to have_no_css("[data-testid='document-upload-button']")
      expect(page).to have_no_text("Certificate of incorporation")

      move_to_documents_stage
      refresh_chat

      expect(page).to have_css("[data-testid='document-upload-button']")
      expect(page).to have_text("Certificate of incorporation")
      expect(page).to have_button("Can't upload now")
    end

    it "keeps what the applicant was typing" do
      sign_in_and_open_chat
      fill_in "message", with: "half a sentence"

      move_to_documents_stage
      refresh_chat

      expect(page).to have_css("[data-testid='document-upload-button']")
      expect(page).to have_field("message", with: "half a sentence")
    end

    it "keeps the upload button working after the swap" do
      sign_in_and_open_chat
      move_to_documents_stage
      refresh_chat
      expect(page).to have_css("[data-testid='document-upload-button']")

      clicked = page.evaluate_script(<<~JS)
        (() => {
          let opened = false
          document.getElementById("onboarding_document_upload").addEventListener("click", (event) => { opened = true; event.preventDefault() })
          document.querySelector("[data-testid='document-upload-button']").click()
          return opened
        })()
      JS
      expect(clicked).to be(true)
    end

    it "hides the checklist and the upload button again when they stop applying" do
      move_to_documents_stage
      sign_in_and_open_chat
      expect(page).to have_text("Certificate of incorporation")

      onboarding_session.update!(current_stage: :business_activity)
      refresh_chat

      expect(page).to have_no_css("[data-testid='document-upload-button']")
      expect(page).to have_no_text("Certificate of incorporation")
    end

    it "still shows them on a fresh load in the documents stage" do
      move_to_documents_stage
      sign_in_and_open_chat

      expect(page).to have_css("[data-testid='document-upload-button']")
      expect(page).to have_text("Certificate of incorporation")
    end
  end

  describe "the last message above new buttons (MH-421)" do
    let(:profile) { create(:registry_profile, applicant: applicant, company_name: "ACME WIDGETS LIMITED") }

    before do
      create(:registry_address, registry_profile: profile, line1: "International House, 10 Churchill Way",
                                city: "Cardiff", postcode: "CF10 2HE")
      onboarding_session.update!(current_stage: :company_info, stage_data: { "company_info" => {
        "company_name" => "Acme Widgets", "company_type" => "limited_company",
        "country_of_incorporation" => "United Kingdom", "registration_number" => "12345678"
      } })
      10.times do |i|
        create(:onboarding_message, onboarding_session: onboarding_session, role: i.even? ? :bot : :applicant,
                                    content: "Earlier message number #{i} " * 6)
      end
    end

    def show_registry_card
      allow(Registry::Lookup).to receive(:call).and_return(Registry::Lookup::Result.success(profile))
      Onboarding::RegistryCompanyCheck.run!(onboarding_session)
      create(:onboarding_message, onboarding_session: onboarding_session, role: :bot,
                                  content: Onboarding::RegistryCompanyCheck.prompt(onboarding_session))
    end

    # The last bubble's bottom edge against the top of what sits below the messages.
    def gap_above_buttons
      page.evaluate_script(<<~JS)
        (() => {
          const list = document.getElementById("onboarding_messages")
          const last = list.lastElementChild.getBoundingClientRect()
          const buttons = document.querySelector("[data-testid=registry-check]").getBoundingClientRect()
          return buttons.top - last.bottom
        })()
      JS
    end

    [ [ 1280, 800 ], [ 375, 700 ] ].each do |width, height|
      it "keeps the whole card visible when its buttons arrive after a reply, at #{width}px" do
        page.driver.resize(width, height)
        sign_in_and_open_chat
        expect(page).to have_no_button("Yes, that's it")

        show_registry_card
        refresh_chat

        expect(page).to have_button("Yes, that's it")
        sleep 0.3
        expect(gap_above_buttons).to be >= 0
      end
    end

    it "leaves an applicant who scrolled up where they were" do
      sign_in_and_open_chat
      # The chat scrolls itself to the latest message on load; wait for that, then scroll up.
      expect(page).to have_css("#onboarding_messages")
      Timeout.timeout(5) { sleep 0.1 until page.evaluate_script("document.getElementById('onboarding_messages').scrollTop") > 0 }
      page.execute_script("document.getElementById('onboarding_messages').scrollTop = 0")

      show_registry_card
      refresh_chat

      expect(page).to have_button("Yes, that's it")
      sleep 0.3
      expect(page.evaluate_script("document.getElementById('onboarding_messages').scrollTop")).to eq(0)
    end
  end
end
