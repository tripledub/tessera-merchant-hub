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
          registry_profile: registry_profile, name: "Example Holdings Ltd",
          kind: "corporate-entity-person-with-significant-control",
          natures_of_control: [ "ownership-of-shares-75-to-100-percent" ], ceased_on: nil)
      end

      it "flags corporate PSCs as UBOs too" do
        expect { call }.to change(Kyc::ValidationWarning, :count).by(1)
        expect(Kyc::ValidationWarning.last.typed_metadata.individual_name).to eq("Example Holdings Ltd")
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

    # MH-313: the registry-side equivalent of Kyc::NomineeDetector's own
    # jurisdiction check, since NomineeDetector only ever reads
    # document-extracted Kyc::CorporateEntity rows.
    context "with a corporate PSC registered in a nominee jurisdiction" do
      before do
        create(:registry_person_with_significant_control,
          registry_profile: registry_profile, name: "Cyprus Nominee Holdings Ltd",
          kind: "corporate-entity-person-with-significant-control",
          natures_of_control: [ "ownership-of-shares-75-to-100-percent" ], ceased_on: nil, country: "CY")
      end

      it "flags a nominee_detected warning, with no corporate_entity link" do
        call

        warning = Kyc::ValidationWarning.find_by(applicant: applicant, warning_type: :nominee_detected)
        expect(warning).to be_present
        expect(warning.corporate_entity).to be_nil
        expect(warning.message).to include("Cyprus Nominee Holdings Ltd").and include("CY")
        expect(warning.typed_metadata.jurisdiction).to eq("CY")
      end

      it "reuses Kyc::NomineeDetector's own jurisdiction list rather than a separate copy" do
        expect(described_class::NOMINEE_JURISDICTIONS).to equal(Kyc::NomineeDetector::NOMINEE_JURISDICTIONS)
      end
    end

    context "with an individual PSC in a non-nominee jurisdiction" do
      before do
        create(:registry_person_with_significant_control,
          registry_profile: registry_profile, name: "Mr Albert Edward Short",
          kind: "individual-person-with-significant-control", country: "United Kingdom", ceased_on: nil)
      end

      it "does not flag a nominee warning" do
        call

        expect(Kyc::ValidationWarning.where(applicant: applicant, warning_type: :nominee_detected)).to be_empty
      end
    end

    context "with a corporate PSC in a nominee jurisdiction that is not itself flagged (individual)" do
      before do
        create(:registry_person_with_significant_control,
          registry_profile: registry_profile, name: "Individual in Cyprus",
          kind: "individual-person-with-significant-control", country: "CY", ceased_on: nil)
      end

      it "does not flag an individual PSC, even in a nominee jurisdiction" do
        call

        expect(Kyc::ValidationWarning.where(applicant: applicant, warning_type: :nominee_detected)).to be_empty
      end
    end

    # MH-313: the registry-side equivalent of Kyc::OwnershipPercentageValidator
    # — but overshoot only (see the method comment for why undershoot is
    # never flagged from banded PSC data).
    context "when active PSCs' lower-bound percentages sum to more than 100%" do
      before do
        create(:registry_person_with_significant_control,
          registry_profile: registry_profile, name: "Majority Owner",
          natures_of_control: [ "ownership-of-shares-75-to-100-percent" ], ceased_on: nil)
        create(:registry_person_with_significant_control,
          registry_profile: registry_profile, name: "Second Owner",
          natures_of_control: [ "ownership-of-shares-50-to-75-percent" ], ceased_on: nil)
      end

      it "flags a percentage_deviation warning, with no corporate_entity link" do
        call

        warning = Kyc::ValidationWarning.find_by(applicant: applicant, warning_type: :percentage_deviation)
        expect(warning).to be_present
        expect(warning.corporate_entity).to be_nil
        expect(warning.typed_metadata.expected).to eq(100.0)
        expect(warning.typed_metadata.actual).to eq(125.0)
      end
    end

    context "when a single PSC's lower-bound percentage is below 100% (the common case)" do
      before do
        create(:registry_person_with_significant_control,
          registry_profile: registry_profile, name: "Majority Owner",
          natures_of_control: [ "ownership-of-shares-75-to-100-percent" ], ceased_on: nil)
      end

      it "does not flag a percentage_deviation warning" do
        call

        expect(Kyc::ValidationWarning.where(applicant: applicant, warning_type: :percentage_deviation)).to be_empty
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
