# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::OwnershipFromRegistry do
  let(:applicant) { create(:applicant, company_name: "Acme Ltd") }
  let(:registry_profile) { create(:registry_profile, applicant: applicant, company_name: "Acme Ltd") }

  def call
    described_class.call(registry_profile)
  end

  describe ".call" do
    context "when there are no active PSCs" do
      it "does nothing" do
        expect { call }.not_to change(Kyc::ValidationWarning, :count)
      end
    end

    context "with an active individual PSC with a numeric ownership band" do
      before do
        create(:registry_person_with_significant_control,
          registry_profile: registry_profile, name: "Mr Albert Edward Short",
          kind: "individual-person-with-significant-control",
          natures_of_control: [ "ownership-of-shares-75-to-100-percent" ], ceased_on: nil)
      end

      it "does not create any Kyc::CorporateEntity or Kyc::OwnershipEdge rows" do
        expect { call }.not_to change(Kyc::CorporateEntity, :count)
        expect(Kyc::OwnershipEdge.count).to eq(0)
      end

      it "directly flags the PSC as a UBO, with no corporate_entity link" do
        expect { call }.to change(Kyc::ValidationWarning, :count).by(1)

        warning = Kyc::ValidationWarning.last
        expect(warning.warning_type).to eq("ubo_threshold_exceeded")
        expect(warning.corporate_entity).to be_nil
        expect(warning.kyc_document).to be_nil
        expect(warning.typed_metadata.individual_name).to eq("Mr Albert Edward Short")
        expect(warning.typed_metadata.effective_percentage).to eq(75)
        expect(warning.typed_metadata.threshold).to eq(25.0)
      end

      it "describes an individual PSC as a person" do
        call

        expect(Kyc::ValidationWarning.last.message).to include("is a person with significant control of")
      end
    end

    context "with an active PSC whose natures_of_control has no numeric band (control only)" do
      before do
        create(:registry_person_with_significant_control,
          registry_profile: registry_profile, name: "Ms Control Only",
          kind: "individual-person-with-significant-control",
          natures_of_control: [ "significant-influence-or-control" ], ceased_on: nil)
      end

      it "still flags them as a UBO, with a nil percentage" do
        call

        warning = Kyc::ValidationWarning.find_by(applicant: applicant)
        expect(warning.typed_metadata.individual_name).to eq("Ms Control Only")
        expect(warning.typed_metadata.effective_percentage).to be_nil
      end
    end

    context "with an active corporate PSC" do
      before do
        create(:registry_person_with_significant_control,
          registry_profile: registry_profile, name: "Hexopay Holdings Limited",
          kind: "corporate-entity-person-with-significant-control",
          natures_of_control: [ "ownership-of-shares-75-to-100-percent" ], ceased_on: nil)
      end

      it "flags corporate PSCs as UBOs too" do
        expect { call }.to change(Kyc::ValidationWarning, :count).by(1)
        expect(Kyc::ValidationWarning.last.typed_metadata.individual_name).to eq("Hexopay Holdings Limited")
      end

      it "describes a corporate PSC as a company, not a person" do
        call

        expect(Kyc::ValidationWarning.last.message).to include("is a company with significant control of")
      end
    end

    context "with a ceased PSC" do
      before do
        create(:registry_person_with_significant_control,
          registry_profile: registry_profile, name: "Former PSC", ceased_on: Date.new(2020, 1, 1))
      end

      it "does not create a UBO warning for them" do
        call
        expect(Kyc::ValidationWarning.where(applicant: applicant)).to be_empty
      end
    end

    context "when called again after an existing registry-derived UBO warning exists" do
      before do
        create(:registry_person_with_significant_control,
          registry_profile: registry_profile, name: "Mr Albert Edward Short", ceased_on: nil)
      end

      it "is idempotent — replaces rather than duplicates" do
        call

        expect { call }.not_to change(Kyc::ValidationWarning, :count)
      end
    end

    context "when the applicant already has document-extracted UBO warnings" do
      let(:kyc_document) { create(:kyc_document, applicant: applicant, document_type: :group_structure_chart) }
      let(:entity) { create(:kyc_corporate_entity, applicant: applicant, kyc_document: kyc_document) }

      before do
        create(:kyc_validation_warning,
          applicant: applicant, kyc_document: kyc_document, corporate_entity: entity,
          warning_type: :ubo_threshold_exceeded, message: "Document-derived UBO")
        create(:registry_person_with_significant_control,
          registry_profile: registry_profile, name: "Mr Albert Edward Short", ceased_on: nil)
      end

      it "does not touch document-derived UBO warnings" do
        expect { call }.not_to change {
          Kyc::ValidationWarning.where(applicant: applicant, corporate_entity: entity).count
        }
      end
    end
  end
end
