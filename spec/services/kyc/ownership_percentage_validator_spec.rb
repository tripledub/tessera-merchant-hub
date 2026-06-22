# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::OwnershipPercentageValidator, type: :service do
  let(:applicant) { create(:applicant) }
  let(:document) { create(:kyc_document, applicant: applicant, document_type: :group_structure_chart) }

  def create_entity(name:, entity_type: :corporate)
    create(:kyc_corporate_entity, applicant: applicant, kyc_document: document, name: name, entity_type: entity_type)
  end

  def create_edge(parent:, child:, percentage:, relationship_type: :equity)
    Kyc::OwnershipEdge.create!(
      parent_entity: parent,
      child_entity: child,
      relationship_type: relationship_type,
      percentage: percentage,
      source_document: document
    )
  end

  describe ".call" do
    context "when equity edges sum to exactly 100%" do
      it "creates no warnings" do
        parent_a = create_entity(name: "Alice Smith", entity_type: :individual)
        parent_b = create_entity(name: "Bob Jones", entity_type: :individual)
        child = create_entity(name: "Acme Holdings Ltd")

        create_edge(parent: parent_a, child: child, percentage: 60.0)
        create_edge(parent: parent_b, child: child, percentage: 40.0)

        expect { described_class.call(document) }
          .not_to change(Kyc::ValidationWarning, :count)
      end
    end

    context "when equity edges sum to within tolerance" do
      it "creates no warnings for 0.3% deviation" do
        parent = create_entity(name: "Alice Smith", entity_type: :individual)
        child = create_entity(name: "Acme Holdings Ltd")

        create_edge(parent: parent, child: child, percentage: 99.7)

        expect { described_class.call(document) }
          .not_to change(Kyc::ValidationWarning, :count)
      end
    end

    context "when equity edges deviate beyond tolerance" do
      it "creates a percentage_deviation warning" do
        parent = create_entity(name: "Alice Smith", entity_type: :individual)
        child = create_entity(name: "Acme Holdings Ltd")

        create_edge(parent: parent, child: child, percentage: 75.0)

        expect { described_class.call(document) }
          .to change(Kyc::ValidationWarning, :count).by(1)

        warning = Kyc::ValidationWarning.last
        expect(warning).to have_attributes(
          warning_type: "percentage_deviation",
          corporate_entity: child,
          applicant: applicant,
          kyc_document: document
        )
        expect(warning.message).to include("Acme Holdings Ltd")
        expect(warning.message).to include("75.0%")
        expect(warning.metadata.expected).to eq(100.0)
        expect(warning.metadata.actual).to eq(75.0)
        expect(warning.metadata.deviation).to eq(25.0)
      end
    end

    context "when multiple nodes have deviations" do
      it "creates a warning per node" do
        person = create_entity(name: "Alice Smith", entity_type: :individual)
        company_a = create_entity(name: "Alpha Corp")
        company_b = create_entity(name: "Beta Ltd")

        create_edge(parent: person, child: company_a, percentage: 80.0)
        create_edge(parent: person, child: company_b, percentage: 60.0)

        expect { described_class.call(document) }
          .to change(Kyc::ValidationWarning, :count).by(2)
      end
    end

    context "with nominee and contractual edges" do
      it "excludes them from the sum" do
        person = create_entity(name: "Alice Smith", entity_type: :individual)
        nominee = create_entity(name: "Nominee Corp")
        child = create_entity(name: "Acme Holdings Ltd")

        create_edge(parent: person, child: child, percentage: 100.0)
        create_edge(parent: nominee, child: child, percentage: 100.0, relationship_type: :nominee)
        create_edge(parent: person, child: child, percentage: nil, relationship_type: :contractual)

        expect { described_class.call(document) }
          .not_to change(Kyc::ValidationWarning, :count)
      end
    end

    context "with entities that have no inbound equity edges" do
      it "skips them (no warning for 0% ownership)" do
        create_entity(name: "Alice Smith", entity_type: :individual)

        expect { described_class.call(document) }
          .not_to change(Kyc::ValidationWarning, :count)
      end
    end

    context "when ownership exceeds 100%" do
      it "creates a warning for overflow" do
        parent_a = create_entity(name: "Alice Smith", entity_type: :individual)
        parent_b = create_entity(name: "Bob Jones", entity_type: :individual)
        child = create_entity(name: "Acme Holdings Ltd")

        create_edge(parent: parent_a, child: child, percentage: 60.0)
        create_edge(parent: parent_b, child: child, percentage: 50.0)

        expect { described_class.call(document) }
          .to change(Kyc::ValidationWarning, :count).by(1)

        warning = Kyc::ValidationWarning.last
        expect(warning.metadata.actual).to eq(110.0)
        expect(warning.metadata.deviation).to eq(10.0)
      end
    end
  end
end
