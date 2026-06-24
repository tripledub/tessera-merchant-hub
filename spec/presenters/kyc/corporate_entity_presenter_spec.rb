# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::CorporateEntityPresenter, type: :presenter do
  let(:template) { ApplicationController.new.view_context }
  let(:applicant) { create(:applicant) }
  let(:document) { create(:kyc_document, applicant: applicant, document_type: :group_structure_chart) }
  let(:entity) { create(:kyc_corporate_entity, applicant: applicant, kyc_document: document) }
  let(:presenter) { described_class.new(entity, template) }

  describe "#entity_type_badge" do
    it "returns blue badge for individuals" do
      individual = create(:kyc_corporate_entity, applicant: applicant, kyc_document: document,
                          entity_type: :individual, name: "Person A")
      p = described_class.new(individual, template)
      html = p.entity_type_badge
      expect(html).to include("Individual")
      expect(html).to include("bg-blue-50")
    end

    it "returns gray badge for corporates" do
      html = presenter.entity_type_badge
      expect(html).to include("Corporate")
      expect(html).to include("bg-gray-100")
    end
  end

  describe "#inbound_edges" do
    it "returns edges where entity is the child" do
      parent = create(:kyc_corporate_entity, applicant: applicant, kyc_document: document, name: "Parent Corp")
      edge = create(:kyc_ownership_edge, parent_entity: parent, child_entity: entity)
      expect(presenter.inbound_edges).to include(edge)
    end
  end

  describe "#outbound_edges" do
    it "returns edges where entity is the parent" do
      child = create(:kyc_corporate_entity, applicant: applicant, kyc_document: document, name: "Child Corp")
      edge = create(:kyc_ownership_edge, parent_entity: entity, child_entity: child)
      expect(presenter.outbound_edges).to include(edge)
    end
  end

  describe "#matched_principal" do
    it "returns matching principal when names match" do
      individual = create(:kyc_corporate_entity, applicant: applicant, kyc_document: document,
                          entity_type: :individual, name: "Test Person")
      create(:kyc_principal, applicant: applicant, name: "Test Person")
      p = described_class.new(individual, template)
      expect(p.matched_principal).to be_present
      expect(p.matched_principal.name).to eq("Test Person")
    end

    it "returns nil when no principal matches" do
      individual = create(:kyc_corporate_entity, applicant: applicant, kyc_document: document,
                          entity_type: :individual, name: "No Match Person")
      p = described_class.new(individual, template)
      expect(p.matched_principal).to be_nil
    end

    it "returns nil for corporate entities" do
      expect(presenter.matched_principal).to be_nil
    end
  end

  describe "#relationship_type_badge" do
    let(:child) { create(:kyc_corporate_entity, applicant: applicant, kyc_document: document, name: "Child Corp") }

    it "returns green badge for equity" do
      edge = create(:kyc_ownership_edge, parent_entity: entity, child_entity: child, relationship_type: :equity)
      html = presenter.relationship_type_badge(edge)
      expect(html).to include("Equity")
      expect(html).to include("bg-green-50")
    end

    it "returns amber badge for nominee" do
      edge = create(:kyc_ownership_edge, parent_entity: entity, child_entity: child, relationship_type: :nominee)
      html = presenter.relationship_type_badge(edge)
      expect(html).to include("Nominee")
      expect(html).to include("bg-amber-50")
    end

    it "returns gray badge for contractual" do
      edge = create(:kyc_ownership_edge, parent_entity: entity, child_entity: child,
                    relationship_type: :contractual, percentage: nil)
      html = presenter.relationship_type_badge(edge)
      expect(html).to include("Contractual")
      expect(html).to include("bg-gray-100")
    end
  end

  describe "#formatted_percentage" do
    let(:child) { create(:kyc_corporate_entity, applicant: applicant, kyc_document: document, name: "Child Corp") }

    it "formats percentage with % sign" do
      edge = create(:kyc_ownership_edge, parent_entity: entity, child_entity: child, percentage: 51.5)
      expect(presenter.formatted_percentage(edge)).to eq("51.5%")
    end

    it "returns dash for nil percentage" do
      edge = create(:kyc_ownership_edge, parent_entity: entity, child_entity: child,
                    percentage: nil, relationship_type: :contractual)
      expect(presenter.formatted_percentage(edge)).to eq("—")
    end
  end
end
