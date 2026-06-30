# frozen_string_literal: true

require "rails_helper"

RSpec.describe Onboarding::DocumentCollectionService do
  let(:applicant) { create(:applicant) }
  let(:session) { create(:onboarding_session, applicant: applicant, stage_data: stage_data) }
  let(:stage_data) { {} }

  describe ".generate_checklist" do
    context "with declared principals" do
      let!(:principal_a) { create(:kyc_principal, applicant: applicant, name: "Person Alpha", source: :applicant_declared) }
      let!(:principal_b) { create(:kyc_principal, applicant: applicant, name: "Person Beta", source: :applicant_declared) }

      it "creates identity and address items for each declared principal" do
        checklist = described_class.generate_checklist(session)

        expect(checklist.size).to eq(4)

        identity_items = checklist.select { |i| i["category"] == "identity" }
        address_items = checklist.select { |i| i["category"] == "proof_of_address" }

        expect(identity_items.map { |i| i["subject"] }).to contain_exactly("Person Alpha", "Person Beta")
        expect(address_items.map { |i| i["subject"] }).to contain_exactly("Person Alpha", "Person Beta")

        expect(identity_items.first["document_types"]).to eq(%w[passport driving_licence])
        expect(address_items.first["document_types"]).to eq(%w[utility_bill])
      end

      it "ignores document_extracted principals" do
        create(:kyc_principal, applicant: applicant, name: "Extracted Person", source: :document_extracted)

        checklist = described_class.generate_checklist(session)
        subjects = checklist.map { |i| i["subject"] }

        expect(subjects).not_to include("Extracted Person")
      end
    end

    context "with company_info in stage_data" do
      let(:stage_data) { { "company_info" => { "company_name" => "Test Co" } } }

      it "includes certificate_of_incorporation" do
        checklist = described_class.generate_checklist(session)

        corp_items = checklist.select { |i| i["category"] == "corporate" }
        expect(corp_items.size).to eq(1)
        expect(corp_items.first["document_types"]).to eq(%w[certificate_of_incorporation])
        expect(corp_items.first["label"]).to eq("Certificate of incorporation")
      end
    end

    context "without company_info in stage_data" do
      let(:stage_data) { {} }

      it "does not include certificate_of_incorporation" do
        checklist = described_class.generate_checklist(session)
        expect(checklist.select { |i| i["category"] == "corporate" }).to be_empty
      end
    end

    context "with nominee ownership edges" do
      let(:doc) { create(:kyc_document, applicant: applicant) }
      let(:parent_entity) { create(:kyc_corporate_entity, applicant: applicant, kyc_document: doc) }
      let(:child_entity) { create(:kyc_corporate_entity, applicant: applicant, kyc_document: doc) }

      before do
        create(:kyc_ownership_edge, parent_entity: parent_entity, child_entity: child_entity, relationship_type: :nominee)
      end

      it "includes declaration_of_trust" do
        checklist = described_class.generate_checklist(session)

        legal_items = checklist.select { |i| i["category"] == "legal" }
        expect(legal_items.size).to eq(1)
        expect(legal_items.first["document_types"]).to eq(%w[declaration_of_trust])
      end
    end

    context "without nominee ownership edges" do
      let(:doc) { create(:kyc_document, applicant: applicant) }
      let(:parent_entity) { create(:kyc_corporate_entity, applicant: applicant, kyc_document: doc) }
      let(:child_entity) { create(:kyc_corporate_entity, applicant: applicant, kyc_document: doc) }

      before do
        create(:kyc_ownership_edge, parent_entity: parent_entity, child_entity: child_entity, relationship_type: :equity)
      end

      it "does not include declaration_of_trust" do
        checklist = described_class.generate_checklist(session)
        expect(checklist.select { |i| i["category"] == "legal" }).to be_empty
      end
    end

    it "persists checklist to session.document_checklist" do
      create(:kyc_principal, applicant: applicant, name: "Person Alpha", source: :applicant_declared)

      described_class.generate_checklist(session)
      session.reload

      expect(session.document_checklist).to be_an(Array)
      expect(session.document_checklist.size).to eq(2)
    end
  end

  describe ".received_documents" do
    let!(:principal) { create(:kyc_principal, applicant: applicant, name: "Person Alpha", source: :applicant_declared) }

    before do
      described_class.generate_checklist(session)
    end

    it "marks items as received when matching documents exist" do
      create(:kyc_document, applicant: applicant, kyc_principal: principal, document_type: :passport)

      result = described_class.received_documents(session)

      identity_item = result.find { |i| i["category"] == "identity" }
      address_item = result.find { |i| i["category"] == "proof_of_address" }

      expect(identity_item["received"]).to be true
      expect(address_item["received"]).to be false
    end

    it "matches driving_licence as identity" do
      create(:kyc_document, applicant: applicant, kyc_principal: principal, document_type: :driving_licence)

      result = described_class.received_documents(session)
      identity_item = result.find { |i| i["category"] == "identity" }
      expect(identity_item["received"]).to be true
    end

    it "matches by principal name for identity and address categories" do
      other_principal = create(:kyc_principal, applicant: applicant, name: "Other Person", source: :applicant_declared)
      create(:kyc_document, applicant: applicant, kyc_principal: other_principal, document_type: :passport)

      # Re-generate to include both principals
      described_class.generate_checklist(session)
      result = described_class.received_documents(session)

      alpha_identity = result.find { |i| i["category"] == "identity" && i["subject"] == "Person Alpha" }
      other_identity = result.find { |i| i["category"] == "identity" && i["subject"] == "Other Person" }

      expect(alpha_identity["received"]).to be false
      expect(other_identity["received"]).to be true
    end

    it "matches corporate documents without principal" do
      session.update!(stage_data: { "company_info" => { "name" => "Test" } })
      described_class.generate_checklist(session)

      create(:kyc_document, applicant: applicant, document_type: :certificate_of_incorporation)

      result = described_class.received_documents(session)
      corp_item = result.find { |i| i["category"] == "corporate" }
      expect(corp_item["received"]).to be true
    end

    it "returns empty array when checklist is blank" do
      session.update!(document_checklist: {})
      expect(described_class.received_documents(session)).to eq([])
    end
  end

  describe ".outstanding_items" do
    let!(:principal) { create(:kyc_principal, applicant: applicant, name: "Person Alpha", source: :applicant_declared) }

    before do
      described_class.generate_checklist(session)
    end

    it "returns only items not yet received" do
      create(:kyc_document, applicant: applicant, kyc_principal: principal, document_type: :passport)

      outstanding = described_class.outstanding_items(session)

      expect(outstanding.size).to eq(1)
      expect(outstanding.first["category"]).to eq("proof_of_address")
    end

    it "returns all items when nothing uploaded" do
      outstanding = described_class.outstanding_items(session)
      expect(outstanding.size).to eq(2)
    end
  end

  describe ".all_received?" do
    context "when checklist is blank" do
      it "returns false" do
        session.update!(document_checklist: {})
        expect(described_class.all_received?(session)).to be false
      end
    end

    context "when all items received" do
      let!(:principal) { create(:kyc_principal, applicant: applicant, name: "Person Alpha", source: :applicant_declared) }

      before do
        described_class.generate_checklist(session)
        create(:kyc_document, applicant: applicant, kyc_principal: principal, document_type: :passport)
        create(:kyc_document, applicant: applicant, kyc_principal: principal, document_type: :utility_bill)
      end

      it "returns true" do
        expect(described_class.all_received?(session)).to be true
      end
    end

    context "when some items outstanding" do
      let!(:principal) { create(:kyc_principal, applicant: applicant, name: "Person Alpha", source: :applicant_declared) }

      before do
        described_class.generate_checklist(session)
        create(:kyc_document, applicant: applicant, kyc_principal: principal, document_type: :passport)
      end

      it "returns false" do
        expect(described_class.all_received?(session)).to be false
      end
    end
  end
end
