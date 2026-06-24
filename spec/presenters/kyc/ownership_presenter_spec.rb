# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::OwnershipPresenter, type: :presenter do
  let(:template) do
    controller = ApplicationController.new
    controller.request = ActionDispatch::TestRequest.create
    controller.view_context
  end
  let(:applicant) { create(:applicant) }
  let(:document) { create(:kyc_document, applicant: applicant, document_type: :group_structure_chart) }
  let(:presenter) { described_class.new(applicant, template) }

  describe "#has_data?" do
    it "returns false when no entities exist" do
      expect(presenter.has_data?).to be false
    end

    it "returns true when entities exist" do
      create(:kyc_corporate_entity, applicant: applicant, kyc_document: document)
      expect(presenter.has_data?).to be true
    end
  end

  describe "#entity_type_badge" do
    it "returns blue badge for individuals" do
      entity = create(:kyc_corporate_entity, applicant: applicant, kyc_document: document, entity_type: :individual)
      html = presenter.entity_type_badge(entity)
      expect(html).to include("Individual")
      expect(html).to include("bg-blue-50")
    end

    it "returns gray badge for corporates" do
      entity = create(:kyc_corporate_entity, applicant: applicant, kyc_document: document, entity_type: :corporate)
      html = presenter.entity_type_badge(entity)
      expect(html).to include("Corporate")
      expect(html).to include("bg-gray-100")
    end
  end

  describe "#relationship_type_badge" do
    let(:parent) { create(:kyc_corporate_entity, applicant: applicant, kyc_document: document) }
    let(:child) { create(:kyc_corporate_entity, applicant: applicant, kyc_document: document, name: "Child Corp") }

    it "returns green badge for equity" do
      edge = create(:kyc_ownership_edge, parent_entity: parent, child_entity: child, relationship_type: :equity)
      html = presenter.relationship_type_badge(edge)
      expect(html).to include("Equity")
      expect(html).to include("bg-green-50")
    end

    it "returns amber badge for nominee" do
      edge = create(:kyc_ownership_edge, parent_entity: parent, child_entity: child, relationship_type: :nominee)
      html = presenter.relationship_type_badge(edge)
      expect(html).to include("Nominee")
      expect(html).to include("bg-amber-50")
    end

    it "returns gray badge for contractual" do
      edge = create(:kyc_ownership_edge, parent_entity: parent, child_entity: child, relationship_type: :contractual, percentage: nil)
      html = presenter.relationship_type_badge(edge)
      expect(html).to include("Contractual")
      expect(html).to include("bg-gray-100")
    end
  end

  describe "#formatted_percentage" do
    let(:parent) { create(:kyc_corporate_entity, applicant: applicant, kyc_document: document) }
    let(:child) { create(:kyc_corporate_entity, applicant: applicant, kyc_document: document, name: "Child Corp") }

    it "formats percentage with % sign" do
      edge = create(:kyc_ownership_edge, parent_entity: parent, child_entity: child, percentage: 61.76)
      expect(presenter.formatted_percentage(edge)).to eq("61.76%")
    end

    it "returns dash for nil percentage" do
      edge = create(:kyc_ownership_edge, parent_entity: parent, child_entity: child, percentage: nil, relationship_type: :contractual)
      expect(presenter.formatted_percentage(edge)).to eq("—")
    end
  end

  describe "counts" do
    before do
      create(:kyc_corporate_entity, applicant: applicant, kyc_document: document, entity_type: :individual, name: "Person A")
      create(:kyc_corporate_entity, applicant: applicant, kyc_document: document, entity_type: :individual, name: "Person B")
      create(:kyc_corporate_entity, applicant: applicant, kyc_document: document, entity_type: :corporate, name: "Corp A")
    end

    it "counts individuals" do
      expect(presenter.individual_count).to eq(2)
    end

    it "counts corporates" do
      expect(presenter.corporate_count).to eq(1)
    end

    it "counts total entities" do
      expect(presenter.entity_count).to eq(3)
    end
  end

  describe "pie chart" do
    let(:corp_a) { create(:kyc_corporate_entity, applicant: applicant, kyc_document: document, entity_type: :corporate, name: "Alpha Corp") }
    let(:corp_b) { create(:kyc_corporate_entity, applicant: applicant, kyc_document: document, entity_type: :corporate, name: "Bravo Ltd") }
    let(:individual) { create(:kyc_corporate_entity, applicant: applicant, kyc_document: document, entity_type: :individual, name: "Jane Doe") }

    before do
      create(:kyc_ownership_edge, parent_entity: individual, child_entity: corp_a, relationship_type: :equity, percentage: 60.0, source_document: document)
      create(:kyc_ownership_edge, parent_entity: corp_b, child_entity: corp_a, relationship_type: :equity, percentage: 40.0, source_document: document)
      create(:kyc_ownership_edge, parent_entity: individual, child_entity: corp_b, relationship_type: :equity, percentage: 100.0, source_document: document)
    end

    describe "#pie_chart_entity" do
      it "returns the corporate entity with most inbound edges" do
        expect(presenter.pie_chart_entity).to eq(corp_a)
      end

      it "excludes individual entities" do
        expect(presenter.pie_chart_entity).not_to eq(individual)
      end
    end

    describe "#pie_chart_data" do
      it "returns data for inbound equity/nominee edges" do
        data = presenter.pie_chart_data(corp_a)
        expect(data.size).to eq(2)
        expect(data.map { |d| d[:name] }).to contain_exactly("Jane Doe", "Bravo Ltd")
      end

      it "includes percentage and relationship type" do
        data = presenter.pie_chart_data(corp_a)
        jane_data = data.find { |d| d[:name] == "Jane Doe" }
        expect(jane_data[:percentage]).to eq(60.0)
        expect(jane_data[:relationship_type]).to eq("equity")
      end
    end

    describe "#pie_chart_links" do
      it "returns one link per inbound edge" do
        data = presenter.pie_chart_data(corp_a)
        links = presenter.pie_chart_links(corp_a)
        expect(links.size).to eq(data.size)
      end
    end
  end
end
