# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::CrossReferenceService, type: :service do
  let(:applicant) { create(:applicant) }
  let(:chart_document) { create(:kyc_document, applicant: applicant, document_type: :group_structure_chart) }
  let!(:corroborating_document) { create(:kyc_document, applicant: applicant, corporate_entity: entity) }

  let(:entity) do
    create(:kyc_corporate_entity, applicant: applicant, kyc_document: chart_document, name: "Target Holdings Ltd")
  end

  let(:adapter) { instance_double(Kyc::Inference::ClaudeAdapter) }

  def create_entity(name:, entity_type: :corporate)
    create(:kyc_corporate_entity, applicant: applicant, kyc_document: chart_document,
           name: name, entity_type: entity_type)
  end

  def create_edge(parent:, child:, percentage: 100.0, relationship_type: :equity)
    Kyc::OwnershipEdge.create!(
      parent_entity: parent,
      child_entity: child,
      relationship_type: relationship_type,
      percentage: percentage,
      source_document: chart_document
    )
  end

  before do
    allow(Kyc::Inference).to receive(:adapter).and_return(adapter)
  end

  describe ".call" do
    context "when document shows a percentage mismatch" do
      it "creates a warning for the deviation" do
        owner = create_entity(name: "Alpha Partners Ltd")
        create_edge(parent: owner, child: entity, percentage: 60.0)

        allow(adapter).to receive(:extract).and_return(
          "shareholders" => [ { "name" => "Alpha Partners Ltd", "percentage" => 55.0 } ]
        )

        expect { described_class.call(entity) }
          .to change(Kyc::ValidationWarning, :count).by(1)

        warning = Kyc::ValidationWarning.last
        expect(warning).to have_attributes(
          warning_type: "cross_reference_discrepancy",
          corporate_entity: entity,
          applicant: applicant,
          kyc_document: corroborating_document
        )

        meta = warning.typed_metadata
        expect(meta.discrepancy_type).to eq("percentage_mismatch")
        expect(meta.chart_percentage).to eq(60.0)
        expect(meta.document_percentage).to eq(55.0)
      end
    end

    context "when document has a shareholder missing from the chart" do
      it "creates a missing_from_chart warning" do
        owner = create_entity(name: "Alpha Partners Ltd")
        create_edge(parent: owner, child: entity, percentage: 100.0)

        allow(adapter).to receive(:extract).and_return(
          "shareholders" => [
            { "name" => "Alpha Partners Ltd", "percentage" => 100.0 },
            { "name" => "Beta Ventures LLC", "percentage" => 10.0 }
          ]
        )

        expect { described_class.call(entity) }
          .to change(Kyc::ValidationWarning, :count).by(1)

        warning = Kyc::ValidationWarning.last
        meta = warning.typed_metadata
        expect(meta.discrepancy_type).to eq("missing_from_chart")
        expect(meta.document_percentage).to eq(10.0)
        expect(meta.chart_percentage).to be_nil
      end
    end

    context "when chart has an owner missing from the document" do
      it "creates a missing_from_document warning" do
        owner_a = create_entity(name: "Alpha Partners Ltd")
        owner_b = create_entity(name: "Gamma Corp")
        create_edge(parent: owner_a, child: entity, percentage: 60.0)
        create_edge(parent: owner_b, child: entity, percentage: 40.0)

        allow(adapter).to receive(:extract).and_return(
          "shareholders" => [ { "name" => "Alpha Partners Ltd", "percentage" => 60.0 } ]
        )

        expect { described_class.call(entity) }
          .to change(Kyc::ValidationWarning, :count).by(1)

        warning = Kyc::ValidationWarning.last
        meta = warning.typed_metadata
        expect(meta.discrepancy_type).to eq("missing_from_document")
        expect(meta.chart_percentage).to eq(40.0)
        expect(meta.document_percentage).to be_nil
      end
    end

    context "when percentage is within tolerance" do
      it "does not create a warning" do
        owner = create_entity(name: "Alpha Partners Ltd")
        create_edge(parent: owner, child: entity, percentage: 60.0)

        allow(adapter).to receive(:extract).and_return(
          "shareholders" => [ { "name" => "Alpha Partners Ltd", "percentage" => 60.3 } ]
        )

        expect { described_class.call(entity) }
          .not_to change(Kyc::ValidationWarning, :count)
      end
    end

    context "when re-run" do
      it "clears previous cross-reference warnings" do
        owner = create_entity(name: "Alpha Partners Ltd")
        create_edge(parent: owner, child: entity, percentage: 60.0)

        # First run — mismatch
        allow(adapter).to receive(:extract).and_return(
          "shareholders" => [ { "name" => "Alpha Partners Ltd", "percentage" => 50.0 } ]
        )
        described_class.call(entity)
        expect(Kyc::ValidationWarning.cross_reference_discrepancy.count).to eq(1)

        # Second run — now matching
        allow(adapter).to receive(:extract).and_return(
          "shareholders" => [ { "name" => "Alpha Partners Ltd", "percentage" => 60.0 } ]
        )
        described_class.call(entity)
        expect(Kyc::ValidationWarning.cross_reference_discrepancy.count).to eq(0)
      end
    end

    context "when inference raises an error" do
      it "logs and does not crash" do
        owner = create_entity(name: "Alpha Partners Ltd")
        create_edge(parent: owner, child: entity, percentage: 60.0)

        allow(adapter).to receive(:extract).and_raise(Kyc::Inference::Error, "API timeout")

        expect { described_class.call(entity) }.not_to raise_error
        expect(Kyc::ValidationWarning.cross_reference_discrepancy.count).to eq(0)
      end
    end

    context "with fuzzy name matching" do
      it "matches similar names and compares percentages" do
        owner = create_entity(name: "Alpha Partners Limited")
        create_edge(parent: owner, child: entity, percentage: 60.0)

        allow(adapter).to receive(:extract).and_return(
          "shareholders" => [ { "name" => "Alpha Partners Ltd", "percentage" => 60.0 } ]
        )

        expect { described_class.call(entity) }
          .not_to change(Kyc::ValidationWarning, :count)
      end
    end
  end
end
