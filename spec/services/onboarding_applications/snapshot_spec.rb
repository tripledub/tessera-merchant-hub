# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingApplications::Snapshot, type: :service do
  let(:applicant) { create(:applicant, company_name: "Acme Widgets Ltd", company_number: "12345678") }
  let(:application) { create(:onboarding_application, applicant: applicant) }

  def fact(snapshot, key) = snapshot.facts.find { |entry| entry.key == key }

  describe "facts" do
    it "reports what the application holds, with its origin" do
      snapshot = described_class.for(application)

      expect(fact(snapshot, :company_name)).to have_attributes(value: "Acme Widgets Ltd", origin: :applicant)
      expect(fact(snapshot, :company_number)).to have_attributes(value: "12345678", origin: :applicant)
    end

    it "omits facts nobody has supplied" do
      applicant.update!(company_number: nil)

      expect(fact(described_class.for(application), :company_number)).to be_nil
    end

    it "reports chat-only answers with the chat as their origin" do
      create(:onboarding_session, applicant: applicant, stage_data: {
        "company_info" => { "company_type" => "limited_company", "country_of_incorporation" => "GB" }
      })

      snapshot = described_class.for(application)

      expect(fact(snapshot, :company_type)).to have_attributes(value: "limited_company", origin: :chat)
      expect(fact(snapshot, :country_of_incorporation)).to have_attributes(value: "GB", origin: :chat)
    end

    it "prefers the application's value when the chat holds the same field" do
      create(:onboarding_session, applicant: applicant, stage_data: {
        "company_info" => { "company_name" => "Chat Version Ltd" }
      })

      expect(fact(described_class.for(application), :company_name))
        .to have_attributes(value: "Acme Widgets Ltd", origin: :applicant)
    end

    it "falls back to the chat's value when the application has none, so both routes report the same fact" do
      applicant.update!(company_name: nil)
      create(:onboarding_session, applicant: applicant, stage_data: {
        "company_info" => { "company_name" => "Acme Widgets Ltd" }
      })

      expect(fact(described_class.for(application), :company_name))
        .to have_attributes(value: "Acme Widgets Ltd", origin: :chat)
    end
  end

  describe "missing items" do
    it "groups gaps by form step for a draft application" do
      snapshot = described_class.for(application)

      expect(snapshot.missing.keys).to include("company", "fulfilment", "currencies", "countries", "principals")
      expect(snapshot.missing["company"]).to include("Business model description can't be blank")
    end

    it "does not list steps that are complete" do
      application.update!(business_model_description: "Sells widgets", operating_licence: "Not required")
      create(:address, :business, :primary, addressable: applicant)
      create(:address, :primary, type: "Address::Trading", addressable: applicant)

      expect(described_class.for(application).missing).not_to have_key("company")
    end

    it "works for a submitted application" do
      application.update!(status: :submitted)

      expect(described_class.for(application).missing).to have_key("company")
    end

    it "lists chat questions the application cannot answer, only when a chat session exists" do
      expect(described_class.for(application).missing).not_to have_key("chat")

      create(:onboarding_session, applicant: applicant, stage_data: {})

      expect(described_class.for(application).missing["chat"]).to include("Company type", "Country of incorporation")
    end

    it "does not ask the chat questions the application has already answered" do
      create(:onboarding_session, applicant: applicant, stage_data: {})

      expect(described_class.for(application).missing["chat"]).not_to include("Company name", "Registration number")
    end
  end

  describe "current step and next action" do
    it "points at the first gap in the current step" do
      application.update!(current_step: "company")

      expect(described_class.for(application).next_action)
        .to have_attributes(step: "company", message: a_string_including("can't be blank"))
    end

    it "falls back to the earliest incomplete step when the current step has no gaps" do
      application.update!(current_step: "volumes")

      expect(described_class.for(application).next_action).to have_attributes(step: "company")
    end

    it "is nil when nothing is outstanding" do
      snapshot = described_class.new(application)
      allow(snapshot).to receive_messages(missing: {}, missing_documents: [])

      expect(snapshot.next_action).to be_nil
    end

    it "reports the application's current step" do
      application.update!(current_step: "countries")

      expect(described_class.for(application).current_step).to eq("countries")
    end
  end

  describe "principals" do
    it "lists name, role, origin and what is still missing for each" do
      create(:kyc_principal, applicant: applicant, name: "Test Director", role: :director, source: :applicant_declared)

      principal = described_class.for(application).principals.first

      expect(principal).to have_attributes(name: "Test Director", role: "director", origin: :applicant)
      expect(principal.missing).to include("Date of birth", "Email", "Proof of identity")
    end

    it "marks registry-fetched principals as coming from the registry" do
      create(:kyc_principal, applicant: applicant, name: "Test Director", source: :registry_fetched)

      expect(described_class.for(application).principals.first.origin).to eq(:registry)
    end

    it "ignores principals that were merged into another" do
      survivor = create(:kyc_principal, applicant: applicant, name: "Test Director")
      create(:kyc_principal, applicant: applicant, name: "Test Director", merged_into: survivor)

      expect(described_class.for(application).principals.map(&:name)).to eq([ "Test Director" ])
    end
  end

  describe "documents" do
    it "lists required and missing documents from the shared KYC policy, before submission" do
      applicant.update!(sector: :crypto_exchange)

      snapshot = described_class.for(application)

      expect(snapshot.required_documents).to include("vasp_registration")
      expect(snapshot.missing_documents).to include("vasp_registration")
    end
  end

  describe "extension point for provenance" do
    it "exposes empty unverified and conflict lists until MH-389 fills them" do
      snapshot = described_class.for(application)

      expect(snapshot.unverified).to eq([])
      expect(snapshot.conflicts).to eq([])
    end
  end

  describe "#for_llm" do
    subject(:context) { described_class.for(application).for_llm }

    let(:applicant) do
      create(:applicant, company_name: "Acme Widgets Ltd", company_number: "12345678", sector: :crypto_exchange)
    end

    before do
      create(:address, :business, :primary, addressable: applicant, line1: "99 Secret Lane", postcode: "ZZ9 9ZZ")
      create(:kyc_principal, applicant: applicant, name: "Test Director", role: :director,
                             source: :applicant_declared, date_of_birth: Date.new(1980, 1, 2),
                             email: "director.private@example.com", address_line1: "7 Private Road",
                             postcode: "AB1 2CD")
      create(:onboarding_session, applicant: applicant, stage_data: {
        "company_info" => { "company_type" => "limited_company", "registered_address" => "99 Secret Lane" }
      })
    end


    it "includes the allow-listed company facts" do
      expect(context[:facts]).to include(company_name: "Acme Widgets Ltd", company_number: "12345678")
    end

    it "includes principals as name, role and what is missing" do
      expect(context[:principals]).to contain_exactly(
        a_hash_including(name: "Test Director", role: "director", missing: a_collection_including("Proof of identity"))
      )
      expect(context[:principals].first.keys).to contain_exactly(:name, :role, :missing)
    end

    it "includes the current step, gaps by step and the next action" do
      expect(context).to include(:current_step, :missing, :next_action)
    end

    it "never contains personal or address data outside the allow-list" do
      serialised = context.to_json

      expect(serialised).not_to include("99 Secret Lane", "ZZ9 9ZZ", "1980", "director.private@example.com",
                                        "7 Private Road", "AB1 2CD")
      expect(context[:facts].keys).to all(be_in(described_class::LLM_FACT_KEYS))
    end
  end
end
