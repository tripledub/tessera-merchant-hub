# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe Kyc::ExecutiveSummary::DataAssembler, type: :service do
  subject(:result) { described_class.call(applicant) }

  let(:applicant) { create(:applicant) }
  let(:document) { create(:kyc_document, applicant: applicant, document_type: :group_structure_chart, status: :complete) }
  let(:id_document) do
    create(:kyc_document, applicant: applicant, document_type: :passport, status: :complete,
           classification_status: :confirmed)
  end

  let!(:corp_entity_a) do
    create(:kyc_corporate_entity, applicant: applicant, kyc_document: document,
           name: "Northwind Holdings Ltd", entity_type: :corporate, jurisdiction: "GB")
  end
  let!(:corp_entity_b) do
    create(:kyc_corporate_entity, applicant: applicant, kyc_document: document,
           name: "Southvale Trading Inc", entity_type: :corporate, jurisdiction: "US")
  end
  let!(:individual_entity) do
    create(:kyc_corporate_entity, applicant: applicant, kyc_document: document,
           name: "Fiona Clearwater", entity_type: :individual, jurisdiction: "GB")
  end

  let!(:equity_edge) do
    create(:kyc_ownership_edge, parent_entity: individual_entity, child_entity: corp_entity_a,
           percentage: 75.0, relationship_type: :equity, source_document: document)
  end
  let!(:nominee_edge) do
    create(:kyc_ownership_edge, parent_entity: corp_entity_a, child_entity: corp_entity_b,
           percentage: 100.0, relationship_type: :nominee, source_document: document)
  end

  let!(:pct_warning) do
    create(:kyc_validation_warning, applicant: applicant, kyc_document: document,
           corporate_entity: corp_entity_a, warning_type: :percentage_deviation,
           message: "Ownership sums to 75%", acknowledged: false)
  end
  let!(:ubo_warning) do
    create(:kyc_validation_warning, applicant: applicant, kyc_document: document,
           corporate_entity: individual_entity, warning_type: :ubo_threshold_exceeded,
           message: "UBO identified: Fiona Clearwater has 75.0% effective ownership",
           metadata: { individual_name: "Fiona Clearwater", effective_percentage: 75.0, threshold: 25.0 },
           acknowledged: true)
  end
  let!(:cross_ref_warning) do
    create(:kyc_validation_warning, applicant: applicant, kyc_document: document,
           corporate_entity: corp_entity_b, warning_type: :cross_reference_discrepancy,
           message: "Director name mismatch between documents", acknowledged: false)
  end

  let!(:principal) do
    create(:kyc_principal, applicant: applicant, name: "Fiona Clearwater")
  end
  let!(:principal_doc) do
    id_document.update!(kyc_principal: principal)
    id_document
  end


  describe "#call" do
    it "returns a hash with all expected sections" do
      expect(result.keys).to match_array(
        %i[ownership edges ubos warnings documents principals compliance cross_references]
      )
    end

    describe "ownership section" do
      subject(:ownership) { result[:ownership] }

      it "counts entities by type" do
        expect(ownership[:entity_count]).to eq(3)
        expect(ownership[:individual_count]).to eq(1)
        expect(ownership[:corporate_count]).to eq(2)
      end

      it "lists unique jurisdictions" do
        expect(ownership[:jurisdictions]).to match_array(%w[GB US])
      end
    end

    describe "edges section" do
      subject(:edges) { result[:edges] }

      it "counts edges by relationship type" do
        expect(edges[:total]).to eq(2)
        expect(edges[:equity_count]).to eq(1)
        expect(edges[:nominee_count]).to eq(1)
        expect(edges[:contractual_count]).to eq(0)
      end
    end

    describe "ubos section" do
      subject(:ubos) { result[:ubos] }

      it "returns UBO entries from validation warnings" do
        expect(ubos.size).to eq(1)
        ubo = ubos.first
        expect(ubo[:name]).to eq("Fiona Clearwater")
        expect(ubo[:percentage]).to eq(75.0)
        expect(ubo[:entity_id]).to eq(individual_entity.id)
      end
    end

    describe "warnings section" do
      subject(:warnings) { result[:warnings] }

      it "aggregates warnings" do
        expect(warnings[:total]).to eq(3)
        expect(warnings[:acknowledged_count]).to eq(1)
        expect(warnings[:unacknowledged_count]).to eq(2)
      end

      it "groups by warning type" do
        expect(warnings[:by_type]).to include(
          "percentage_deviation" => 1,
          "ubo_threshold_exceeded" => 1,
          "cross_reference_discrepancy" => 1
        )
      end
    end

    describe "documents section" do
      subject(:documents) { result[:documents] }

      it "counts documents" do
        expect(documents[:total]).to eq(2)
        expect(documents[:confirmed_count]).to eq(1)
        expect(documents[:extracted_count]).to eq(2)
      end

      it "groups by document type" do
        expect(documents[:by_type]).to include(
          "group_structure_chart" => 1,
          "passport" => 1
        )
      end
    end

    describe "principals section" do
      subject(:principals) { result[:principals] }

      it "includes principal with linked document types" do
        expect(principals.size).to eq(1)
        p = principals.first
        expect(p[:name]).to eq("Fiona Clearwater")
        expect(p[:principal_id]).to eq(principal.id)
        expect(p[:linked_document_types]).to eq(%w[passport])
      end
    end

    describe "compliance section" do
      subject(:compliance) { result[:compliance] }

      it "includes compliance assessment data" do
        expect(compliance).to have_key(:compliant)
        expect(compliance).to have_key(:entity_count)
        expect(compliance).to have_key(:compliant_entity_count)
        expect(compliance).to have_key(:entity_results)
        expect(compliance[:entity_count]).to eq(3)
      end
    end

    describe "cross_references section" do
      subject(:cross_refs) { result[:cross_references] }

      it "returns cross-reference discrepancies" do
        expect(cross_refs.size).to eq(1)
        expect(cross_refs.first[:entity_name]).to eq("Southvale Trading Inc")
        expect(cross_refs.first[:message]).to eq("Director name mismatch between documents")
      end
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
