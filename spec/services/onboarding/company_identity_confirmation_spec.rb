# frozen_string_literal: true

require "rails_helper"

RSpec.describe Onboarding::CompanyIdentityConfirmation do
  let(:applicant) { create(:applicant, company_name: "Acme Widgets Ltd", company_number: "12345678") }
  let(:session) { create(:onboarding_session, applicant: applicant) }

  describe ".pending?" do
    it "is true when the application has a company name and the chat has not started" do
      expect(described_class.pending?(session)).to be(true)
    end

    it "falls back to the name the PSP gave when the applicant has not declared a company name (MH-415)" do
      applicant.update!(company_name: nil, company_number: nil)

      expect(described_class.pending?(session)).to be(true)
    end

    it "is false once the applicant has answered" do
      described_class.confirm!(session)

      expect(described_class.pending?(session.reload)).to be(false)
    end

    it "is false when the conversation has already started" do
      create(:onboarding_message, onboarding_session: session, role: :applicant, content: "Hello")

      expect(described_class.pending?(session)).to be(false)
    end
  end

  describe ".prompt" do
    it "names the company and its number" do
      expect(described_class.prompt(session)).to eq(
        "I have your company as **Acme Widgets Ltd**, company number **12345678**. Is this correct?"
      )
    end

    it "omits the number when none is on file" do
      applicant.update!(company_number: nil)

      expect(described_class.prompt(session)).to eq("I have your company as **Acme Widgets Ltd**. Is this correct?")
    end
  end

  describe ".confirm!" do
    it "copies the name and number into the chat data and moves on to the remaining questions" do
      described_class.confirm!(session)

      session.reload
      expect(session.stage_data["company_info"]).to eq(
        "company_name" => "Acme Widgets Ltd",
        "registration_number" => "12345678"
      )
      expect(session.stage_data["company_identity_check"]).to eq("confirmed")
      reply = session.onboarding_messages.bot.last
      expect(reply.content).to include("Company type", "Registered address", "Country of incorporation")
      expect(reply.content).not_to include("Company name")
    end

    it "copies only the name when no number is on file" do
      applicant.update!(company_number: nil)

      described_class.confirm!(session)

      expect(session.reload.stage_data["company_info"]).to eq("company_name" => "Acme Widgets Ltd")
    end

    it "keeps company details the chat already holds" do
      session.update!(stage_data: { "company_info" => { "company_type" => "limited_company" } })

      described_class.confirm!(session)

      expect(session.reload.stage_data["company_info"]).to include("company_type" => "limited_company")
    end
  end

  describe ".decline!" do
    it "starts fresh without copying anything and asks for the business name" do
      described_class.decline!(session)

      session.reload
      expect(session.stage_data["company_info"]).to be_nil
      expect(session.stage_data["company_identity_check"]).to eq("declined")
      expect(session.onboarding_messages.bot.last.content).to include("name of your business")
    end

    it "leaves the application's stored details untouched" do
      described_class.decline!(session)

      expect(applicant.reload).to have_attributes(company_name: "Acme Widgets Ltd", company_number: "12345678")
    end
  end

  # MH-415: a business added by the PSP has a name but no declared company name yet.
  describe "when only the PSP's name is held" do
    let(:applicant) { create(:applicant, name: "Stew & Co", company_name: nil, company_number: nil) }

    it "names the company from the PSP's name, with no number" do
      expect(described_class.company_name(session)).to eq("Stew & Co")
      expect(described_class.prompt(session)).to eq("I have your company as **Stew & Co**. Is this correct?")
    end

    it "prefers a declared company name over the PSP's name" do
      applicant.update!(company_name: "Stew & Co Ltd")

      expect(described_class.company_name(session)).to eq("Stew & Co Ltd")
    end

    it "on yes, keeps the name as the applicant's own answer, in the chat data and on the applicant" do
      described_class.confirm!(session)

      session.reload
      expect(session.stage_data["company_info"]).to eq("company_name" => "Stew & Co")
      expect(applicant.reload.company_name).to eq("Stew & Co")
      expect(Provenance::CompanyFields.source_for(applicant, "company_name")).to eq(:applicant_declared)
      reply = session.onboarding_messages.bot.last
      expect(reply.content).to include("Company type", "Country of incorporation", "Registered address")
      expect(reply.content).not_to include("Company name")
    end

    it "does not ask for the country when the PSP chose a registry jurisdiction (MH-391)" do
      applicant.update!(registry_jurisdiction: "gb")

      described_class.confirm!(session)

      expect(session.reload.stage_data["company_info"]).to include("country_of_incorporation" => "United Kingdom")
      expect(session.onboarding_messages.bot.last.content).not_to include("Country of incorporation")
    end

    it "never changes the PSP's name, whatever the answer" do
      described_class.confirm!(session)

      expect(applicant.reload.name).to eq("Stew & Co")
    end

    it "on no, asks for the name, and leaves the company name blank" do
      described_class.decline!(session)

      expect(applicant.reload).to have_attributes(name: "Stew & Co", company_name: nil)
      expect(session.reload.stage_data["company_identity_check"]).to eq("declined")
      expect(session.onboarding_messages.bot.last.content).to include("name of your business")
    end

    it "is not pending once the chat has started" do
      create(:onboarding_message, onboarding_session: session, role: :applicant, content: "Hello")

      expect(described_class.pending?(session)).to be(false)
    end
  end
end
