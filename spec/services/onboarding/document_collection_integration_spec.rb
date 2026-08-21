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
    expect(checklist.size).to eq(4) # identity + address + corporate + proof_of_business_address

    # Upload identity document
    create(:kyc_document, applicant: applicant, kyc_principal: principal,
           document_type: :passport, classification_status: :confirmed, status: :complete)

    outstanding = described_class.outstanding_items(session)
    expect(outstanding.size).to eq(3)

    # Upload address document
    create(:kyc_document, applicant: applicant, kyc_principal: principal,
           document_type: :utility_bill, classification_status: :confirmed, status: :complete)

    outstanding = described_class.outstanding_items(session)
    expect(outstanding.size).to eq(2)

    # Upload corporate document (also satisfies proof_of_business_address as cert_of_incorporation is in both lists)
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

  context "with a Crypto Exchange applicant" do
    let(:applicant) { create(:applicant, sector: :crypto_exchange) }

    it "marks each required policy document as received when uploaded" do
      described_class.generate_checklist(session)

      create(:kyc_document, applicant: applicant, document_type: :vasp_registration,
             classification_status: :confirmed, status: :complete)

      received = described_class.received_documents(session)
      expect(received.find { |item| item["requirement_id"] == "crypto.vasp_registration" }["received"]).to be true
      expect(received.find { |item| item["requirement_id"] == "crypto.wallet_custody_infrastructure_attestation" }["received"]).to be false

      create(:kyc_document, applicant: applicant, document_type: :wallet_custody_infrastructure_attestation,
             classification_status: :confirmed, status: :complete)

      received = described_class.received_documents(session)
      expect(received.find { |item| item["requirement_id"] == "crypto.wallet_custody_infrastructure_attestation" }["received"]).to be true
    end
  end
end
