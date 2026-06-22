# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::EffectiveUboCalculator, type: :service do
  let(:applicant) { create(:applicant) }
  let(:document) { create(:kyc_document, applicant: applicant, document_type: :group_structure_chart) }

  def create_entity(name:, entity_type: :corporate)
    create(:kyc_corporate_entity,
      applicant: applicant,
      kyc_document: document,
      name: name,
      entity_type: entity_type)
  end

  def create_edge(parent:, child:, percentage:, relationship_type: :equity)
    create(:kyc_ownership_edge,
      parent_entity: parent,
      child_entity: child,
      percentage: percentage,
      relationship_type: relationship_type,
      source_document: document)
  end

  describe ".call" do
    context "with direct ownership above threshold" do
      it "flags an individual with 100% direct ownership" do
        alice = create_entity(name: "Alice Smith", entity_type: :individual)
        acme = create_entity(name: "Acme Holdings Ltd")
        create_edge(parent: alice, child: acme, percentage: 100.0)

        expect { described_class.call(document) }
          .to change(Kyc::ValidationWarning, :count).by(1)

        warning = Kyc::ValidationWarning.last
        expect(warning.warning_type).to eq("ubo_threshold_exceeded")
        expect(warning.corporate_entity).to eq(alice)
        expect(warning.message).to include("Alice Smith")
        expect(warning.message).to include("100.0%")

        typed = warning.typed_metadata
        expect(typed.individual_name).to eq("Alice Smith")
        expect(typed.effective_percentage).to eq(100.0)
        expect(typed.threshold).to eq(25.0)
      end
    end

    context "with multi-hop chain" do
      it "computes effective ownership through intermediate corporate entity" do
        bob = create_entity(name: "Bob Jones", entity_type: :individual)
        holding = create_entity(name: "Bravo Holdings Ltd")
        target = create_entity(name: "Charlie Corp")

        create_edge(parent: bob, child: holding, percentage: 100.0)
        create_edge(parent: holding, child: target, percentage: 60.0)

        described_class.call(document)

        warnings = Kyc::ValidationWarning.where(warning_type: :ubo_threshold_exceeded)
        target_warning = warnings.find { |w| w.message.include?("Charlie Corp") }
        expect(target_warning).to be_present
        expect(target_warning.typed_metadata.effective_percentage).to eq(60.0)
      end
    end

    context "when below threshold" do
      it "does not create a warning for ownership below 25%" do
        carol = create_entity(name: "Carol White", entity_type: :individual)
        delta = create_entity(name: "Delta Ltd")
        create_edge(parent: carol, child: delta, percentage: 20.0)

        expect { described_class.call(document) }
          .not_to change(Kyc::ValidationWarning, :count)
      end
    end

    context "with diamond ownership" do
      it "sums effective percentages across multiple paths" do
        dave = create_entity(name: "Dave Brown", entity_type: :individual)
        echo = create_entity(name: "Echo Holdings Ltd")
        foxtrot = create_entity(name: "Foxtrot Ltd")
        target = create_entity(name: "Golf Corp")

        # Path 1: Dave -> Echo (100%) -> Golf (15%) = 15%
        create_edge(parent: dave, child: echo, percentage: 100.0)
        create_edge(parent: echo, child: target, percentage: 15.0)

        # Path 2: Dave -> Foxtrot (100%) -> Golf (15%) = 15%
        create_edge(parent: dave, child: foxtrot, percentage: 100.0)
        create_edge(parent: foxtrot, child: target, percentage: 15.0)

        described_class.call(document)

        # Should sum to 30% which exceeds threshold
        warnings = Kyc::ValidationWarning.where(warning_type: :ubo_threshold_exceeded)
        golf_warning = warnings.find { |w| w.message.include?("Golf Corp") }
        expect(golf_warning).to be_present
        expect(golf_warning.typed_metadata.effective_percentage).to eq(30.0)
      end
    end

    context "when nominee/contractual edges present" do
      it "only traverses equity edges" do
        eve = create_entity(name: "Eve Green", entity_type: :individual)
        hotel = create_entity(name: "Hotel Ltd")

        create_edge(parent: eve, child: hotel, percentage: 100.0, relationship_type: :nominee)

        expect { described_class.call(document) }
          .not_to change(Kyc::ValidationWarning, :count)
      end
    end

    context "with multiple individuals, mixed results" do
      it "flags only individuals above threshold" do
        frank = create_entity(name: "Frank Black", entity_type: :individual)
        grace = create_entity(name: "Grace Grey", entity_type: :individual)
        india = create_entity(name: "India Corp")

        create_edge(parent: frank, child: india, percentage: 80.0)
        create_edge(parent: grace, child: india, percentage: 10.0)

        described_class.call(document)

        warnings = Kyc::ValidationWarning.where(warning_type: :ubo_threshold_exceeded)
        expect(warnings.count).to eq(1)
        expect(warnings.first.corporate_entity).to eq(frank)
      end
    end

    context "with no entities" do
      it "does nothing when document has no entities" do
        expect { described_class.call(document) }
          .not_to change(Kyc::ValidationWarning, :count)
      end
    end
  end
end
