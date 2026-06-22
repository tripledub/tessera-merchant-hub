# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::UnresolvedChainDetector, type: :service do
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
    context "when a corporate entity has no inbound equity edges" do
      it "creates an unresolved_chain warning" do
        entity = create_entity(name: "Apex Holdings Ltd")

        expect { described_class.call(document) }
          .to change(Kyc::ValidationWarning, :count).by(1)

        warning = Kyc::ValidationWarning.last
        expect(warning).to have_attributes(
          warning_type: "unresolved_chain",
          corporate_entity: entity,
          applicant: applicant,
          kyc_document: document
        )
        expect(warning.message).to eq("Unresolved ownership: Apex Holdings Ltd has no traced parent — further documentation required")
        expect(warning.typed_metadata).to be_a(Kyc::ValidationWarningMetadata::UnresolvedChain)
        expect(warning.typed_metadata.entity_name).to eq("Apex Holdings Ltd")
      end
    end

    context "when a corporate entity has inbound equity edges" do
      it "does not create a warning" do
        parent = create_entity(name: "Global Corp")
        child = create_entity(name: "Regional Ltd")
        create_edge(parent: parent, child: child, relationship_type: :equity)

        expect { described_class.call(document) }
          .to change(Kyc::ValidationWarning, :count).by(1)

        # Only Global Corp (no inbound equity) gets a warning, not Regional Ltd
        warning = Kyc::ValidationWarning.last
        expect(warning.corporate_entity.name).to eq("Global Corp")
      end
    end

    context "when an individual entity has no inbound edges" do
      it "does not create a warning" do
        create_entity(name: "John Smith", entity_type: :individual)

        expect { described_class.call(document) }
          .not_to change(Kyc::ValidationWarning, :count)
      end
    end

    context "when multiple corporate entities have no inbound equity edges" do
      it "creates one warning per entity" do
        create_entity(name: "Alpha Corp")
        create_entity(name: "Beta Holdings")

        expect { described_class.call(document) }
          .to change(Kyc::ValidationWarning, :count).by(2)

        names = Kyc::ValidationWarning.pluck(:message)
        expect(names).to include(
          "Unresolved ownership: Alpha Corp has no traced parent — further documentation required",
          "Unresolved ownership: Beta Holdings has no traced parent — further documentation required"
        )
      end
    end

    context "when a corporate entity has only nominee inbound edges" do
      it "creates an unresolved_chain warning" do
        parent = create_entity(name: "Nominee Services Ltd")
        child = create_entity(name: "Target Corp")
        create_edge(parent: parent, child: child, relationship_type: :nominee)

        expect { described_class.call(document) }
          .to change(Kyc::ValidationWarning, :count).by(2)

        warned_entities = Kyc::ValidationWarning.all.map { |w| w.corporate_entity.name }
        expect(warned_entities).to include("Target Corp", "Nominee Services Ltd")
      end
    end
  end
end
