# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::NomineeDetector, type: :service do
  let(:applicant) { create(:applicant) }
  let(:document) { create(:kyc_document, applicant: applicant, document_type: :group_structure_chart) }

  def create_entity(name:, entity_type: :corporate, jurisdiction: nil)
    create(:kyc_corporate_entity, applicant: applicant, kyc_document: document,
           name: name, entity_type: entity_type, jurisdiction: jurisdiction)
  end

  def create_edge(parent:, child:, percentage: 100.0, relationship_type: :equity)
    Kyc::OwnershipEdge.create!(
      parent_entity: parent,
      child_entity: child,
      relationship_type: relationship_type,
      percentage: percentage,
      source_document: document
    )
  end

  describe ".call" do
    context "when an edge has relationship_type :nominee" do
      it "creates a nominee_detected warning for the parent entity" do
        parent = create_entity(name: "Cypress Holdings Ltd", jurisdiction: "GB")
        child = create_entity(name: "Acme Corp")
        create_edge(parent: parent, child: child, relationship_type: :nominee)

        expect { described_class.call(document) }
          .to change(Kyc::ValidationWarning, :count).by(1)

        warning = Kyc::ValidationWarning.last
        expect(warning).to have_attributes(
          warning_type: "nominee_detected",
          corporate_entity: parent,
          applicant: applicant,
          kyc_document: document
        )
        expect(warning.message).to include("Cypress Holdings Ltd")
        expect(warning.typed_metadata.detection_reason).to eq("nominee_edge")
      end
    end

    context "when an entity is in a nominee jurisdiction" do
      it "creates a nominee_detected warning" do
        entity = create_entity(name: "Larnaca Trading Ltd", jurisdiction: "CY")
        other = create_entity(name: "Acme Corp")
        create_edge(parent: entity, child: other)

        expect { described_class.call(document) }
          .to change(Kyc::ValidationWarning, :count).by(1)

        warning = Kyc::ValidationWarning.last
        expect(warning.corporate_entity).to eq(entity)
        expect(warning.typed_metadata.detection_reason).to eq("nominee_jurisdiction")
        expect(warning.typed_metadata.jurisdiction).to eq("CY")
      end
    end

    context "when an entity name contains 'nominee'" do
      it "creates a nominee_detected warning" do
        entity = create_entity(name: "Sandret Nominee Ltd", jurisdiction: "GB")

        expect { described_class.call(document) }
          .to change(Kyc::ValidationWarning, :count).by(1)

        warning = Kyc::ValidationWarning.last
        expect(warning.corporate_entity).to eq(entity)
        expect(warning.typed_metadata.detection_reason).to eq("nominee_name")
      end

      it "is case insensitive" do
        create_entity(name: "CORPORATE NOMINEE SERVICES", jurisdiction: "GB")

        expect { described_class.call(document) }
          .to change(Kyc::ValidationWarning, :count).by(1)
      end
    end

    context "when an entity triggers multiple signals" do
      it "creates one warning per signal" do
        entity = create_entity(name: "Cyprus Nominee Holdings", jurisdiction: "CY")
        child = create_entity(name: "Acme Corp")
        create_edge(parent: entity, child: child, relationship_type: :nominee)

        expect { described_class.call(document) }
          .to change(Kyc::ValidationWarning, :count).by(3)
      end
    end

    context "when no nominee signals are present" do
      it "creates no warnings" do
        parent = create_entity(name: "Alice Smith", entity_type: :individual)
        child = create_entity(name: "Acme Holdings Ltd", jurisdiction: "GB")
        create_edge(parent: parent, child: child)

        expect { described_class.call(document) }
          .not_to change(Kyc::ValidationWarning, :count)
      end
    end

    context "with individuals" do
      it "does not flag individuals for jurisdiction" do
        create_entity(name: "Maria Georgiou", entity_type: :individual, jurisdiction: "CY")

        expect { described_class.call(document) }
          .not_to change(Kyc::ValidationWarning, :count)
      end
    end
  end
end
