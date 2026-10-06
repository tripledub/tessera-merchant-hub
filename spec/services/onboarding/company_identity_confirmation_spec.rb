# frozen_string_literal: true

require "rails_helper"

RSpec.describe Onboarding::CompanyIdentityConfirmation do
  let(:applicant) { create(:applicant, company_name: "Acme Widgets Ltd", company_number: "12345678") }
  let(:session) { create(:onboarding_session, applicant: applicant) }

  describe ".pending?" do
    it "is true when the application has a company name and the chat has not started" do
      expect(described_class.pending?(session)).to be(true)
    end

    it "is false when the application has no company name" do
      applicant.update!(company_name: nil, company_number: nil)

      expect(described_class.pending?(session)).to be(false)
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
end
