# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::GroupStructureExtractorService, type: :service do
  let(:applicant) { create(:applicant) }
  let(:document) { create(:kyc_document, applicant: applicant, document_type: :group_structure_chart) }

  let(:raw_response) do
    {
      "entities" => [
        { "name" => "Northwind Holdings Ltd", "type" => "corporate", "jurisdiction" => "GB" },
        { "name" => "Jane Doe", "type" => "individual", "jurisdiction" => nil },
        { "name" => "Southgate Trading Ltd", "type" => "corporate", "jurisdiction" => "CY" }
      ],
      "edges" => [
        { "parent" => "Jane Doe", "child" => "Northwind Holdings Ltd", "relationship_type" => "equity", "percentage" => 100.0 },
        { "parent" => "Northwind Holdings Ltd", "child" => "Southgate Trading Ltd", "relationship_type" => "nominee", "percentage" => 100.0 }
      ]
    }
  end

  let(:mock_adapter) { instance_double(Kyc::Inference::Base) }

  before do
    allow(Kyc::Inference).to receive(:adapter).and_return(mock_adapter)
    allow(mock_adapter).to receive(:extract).with(document: document, prompt: described_class::PROMPT).and_return(raw_response)
  end

  describe ".call" do
    it "creates corporate entity records for each entity" do
      expect { described_class.call(document) }
        .to change(Kyc::CorporateEntity, :count).by(3)
    end

    it "creates ownership edge records for each edge" do
      expect { described_class.call(document) }
        .to change(Kyc::OwnershipEdge, :count).by(2)
    end

    it "sets entity attributes correctly" do
      described_class.call(document)

      entity = Kyc::CorporateEntity.find_by(name: "Northwind Holdings Ltd")
      expect(entity).to have_attributes(
        entity_type: "corporate",
        jurisdiction: "GB",
        applicant_id: applicant.id,
        kyc_document_id: document.id
      )
    end

    it "sets individual entity type correctly" do
      described_class.call(document)

      entity = Kyc::CorporateEntity.find_by(name: "Jane Doe")
      expect(entity.entity_type).to eq("individual")
    end

    it "sets edge attributes correctly" do
      described_class.call(document)

      jane = Kyc::CorporateEntity.find_by(name: "Jane Doe")
      northwind = Kyc::CorporateEntity.find_by(name: "Northwind Holdings Ltd")
      edge = Kyc::OwnershipEdge.find_by(parent_entity: jane, child_entity: northwind)

      expect(edge).to have_attributes(
        relationship_type: "equity",
        percentage: 100.0,
        source_document_id: document.id
      )
    end

    it "sets nominee relationship type correctly" do
      described_class.call(document)

      northwind = Kyc::CorporateEntity.find_by(name: "Northwind Holdings Ltd")
      southgate = Kyc::CorporateEntity.find_by(name: "Southgate Trading Ltd")
      edge = Kyc::OwnershipEdge.find_by(parent_entity: northwind, child_entity: southgate)

      expect(edge.relationship_type).to eq("nominee")
    end

    it "stores the raw response in extracted_data" do
      described_class.call(document)
      document.reload

      expect(document.extracted_data).to have_key("entities")
      expect(document.extracted_data).to have_key("edges")
    end

    it "rolls back all records if an edge references a missing entity" do
      bad_response = raw_response.deep_dup
      bad_response["edges"] << { "parent" => "Ghost Corp", "child" => "Northwind Holdings Ltd", "relationship_type" => "equity", "percentage" => 50.0 }
      allow(mock_adapter).to receive(:extract).and_return(bad_response)

      expect { described_class.call(document) }
        .to raise_error(Kyc::GroupStructureExtractorService::ExtractionError, /entity not found.*Ghost Corp/i)

      expect(Kyc::CorporateEntity.count).to eq(0)
      expect(Kyc::OwnershipEdge.count).to eq(0)
    end

    it "clears previous entities and edges before re-extraction" do
      described_class.call(document)
      expect(Kyc::CorporateEntity.count).to eq(3)

      described_class.call(document)
      expect(Kyc::CorporateEntity.count).to eq(3)
    end

    context "with validation warnings" do
      it "runs ownership percentage validation after extraction" do
        allow(Kyc::OwnershipPercentageValidator).to receive(:call)

        described_class.call(document)

        expect(Kyc::OwnershipPercentageValidator).to have_received(:call).with(document)
      end

      it "runs nominee detection after extraction" do
        allow(Kyc::NomineeDetector).to receive(:call)

        described_class.call(document)

        expect(Kyc::NomineeDetector).to have_received(:call).with(document)
      end

      it "clears previous warnings before re-extraction" do
        described_class.call(document)

        stale = Kyc::ValidationWarning.create!(
          applicant: applicant,
          kyc_document: document,
          warning_type: :percentage_deviation,
          message: "stale warning",
          metadata: { expected: 100.0, actual: 50.0, deviation: 50.0 }
        )

        described_class.call(document)

        expect(Kyc::ValidationWarning.exists?(stale.id)).to be false
      end
    end
  end
end
