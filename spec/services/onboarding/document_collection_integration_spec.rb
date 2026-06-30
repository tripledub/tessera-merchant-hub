# frozen_string_literal: true

require "rails_helper"

RSpec.describe Onboarding::DocumentCollectionService, type: :service do # rubocop:disable RSpec/SpecFilePathFormat
  let(:applicant) { create(:applicant) }
  let(:session) do
    create(:onboarding_session, applicant: applicant, current_stage: :document_collection,
           stage_data: { "company_info" => { "company_name" => "Acme Ltd" } })
  end
  let!(:principal) { create(:kyc_principal, applicant: applicant, name: "Jane Doe", source: :applicant_declared) }

  it "generates checklist, tracks documents, and completes when all received" do
    checklist = described_class.generate_checklist(session)
    expect(checklist.size).to eq(3) # identity + address + corporate

    # Upload identity document
    create(:kyc_document, applicant: applicant, kyc_principal: principal,
           document_type: :passport, classification_status: :confirmed, status: :complete)

    outstanding = described_class.outstanding_items(session)
    expect(outstanding.size).to eq(2)

    # Upload address document
    create(:kyc_document, applicant: applicant, kyc_principal: principal,
           document_type: :utility_bill, classification_status: :confirmed, status: :complete)

    outstanding = described_class.outstanding_items(session)
    expect(outstanding.size).to eq(1)

    # Upload corporate document
    create(:kyc_document, applicant: applicant,
           document_type: :certificate_of_incorporation,
           classification_status: :confirmed, status: :complete)

    expect(described_class.all_received?(session)).to be true
    expect(Onboarding::StateMachine.stage_complete?(session)).to be true
  end

  it "does not complete when documents are missing" do
    described_class.generate_checklist(session)

    create(:kyc_document, applicant: applicant, kyc_principal: principal,
           document_type: :passport, classification_status: :confirmed, status: :complete)

    expect(described_class.all_received?(session)).to be false
    expect(Onboarding::StateMachine.stage_complete?(session)).to be false
  end
end
