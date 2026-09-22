# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::PrincipalMatchOverrideService do
  let_it_be(:applicant) { create(:applicant) }
  let_it_be(:resolver)  { create(:user, :psp_admin) }

  let!(:registry_principal) do
    create(:kyc_principal, applicant: applicant, name: "SAMPLE, Riley", source: :registry_fetched,
      date_of_birth_month: 3, date_of_birth_year: 1985, status: :confirmed)
  end

  let!(:document) do
    create(:kyc_document, applicant: applicant, document_type: :passport, status: :complete,
      dob_mismatch_kyc_principal: registry_principal,
      extracted_data: { "full_name" => "Riley Sample", "date_of_birth" => "1990-06-02" })
  end

  def call(resolution:, reason: "A reason")
    described_class.call(document: document, resolution: resolution, reason: reason, actor: resolver)
  end

  describe "#call" do
    context "with no mismatch on the document" do
      let!(:document) { create(:kyc_document, applicant: applicant, dob_mismatch_kyc_principal: nil) }

      it "fails without creating an audit row" do
        result = nil
        expect { result = call(resolution: "link_anyway") }.not_to change(Kyc::PrincipalMatchOverride, :count)

        expect(result.success?).to be false
        expect(result.errors[:base]).to be_present
      end
    end

    context "with an invalid resolution" do
      it "fails without creating an audit row or changing the document" do
        expect { call(resolution: "bogus") }.not_to change(Kyc::PrincipalMatchOverride, :count)
        expect(document.reload.kyc_principal).to be_nil
      end
    end

    context "when resolving as link_anyway" do
      it "links the document to the mismatched principal" do
        call(resolution: "link_anyway")

        expect(document.reload.kyc_principal).to eq(registry_principal)
        expect(document.match_method).to eq("override_linked")
        expect(document.match_confidence).to eq(1.0)
        expect(document.dob_mismatch_kyc_principal).to be_nil
      end

      it "backfills the principal's full date of birth from the extraction" do
        call(resolution: "link_anyway")

        expect(registry_principal.reload.date_of_birth).to eq(Date.new(1990, 6, 2))
      end

      it "confirms the principal" do
        registry_principal.update!(status: :unconfirmed)

        call(resolution: "link_anyway")

        expect(registry_principal.reload).to be_confirmed
      end

      it "does not create a new principal" do
        expect { call(resolution: "link_anyway") }.not_to change(KycPrincipal, :count)
      end

      it "records an audit row with the required reason" do
        result = call(resolution: "link_anyway", reason: "Same person, CH data error")

        expect(result.success?).to be true
        expect(result.override).to be_link_anyway
        expect(result.override.kyc_principal).to eq(registry_principal)
        expect(result.override.kyc_document).to eq(document)
        expect(result.override.reason).to eq("Same person, CH data error")
        expect(result.override.resolved_by).to eq(resolver)
      end

      it "fails without a reason and makes no changes" do
        result = call(resolution: "link_anyway", reason: nil)

        expect(result.success?).to be false
        expect(document.reload.kyc_principal).to be_nil
      end
    end

    context "when resolving as different_person" do
      it "creates a new unconfirmed, unspecified-role principal from the extraction" do
        expect { call(resolution: "different_person") }.to change(KycPrincipal, :count).by(1)

        new_principal = document.reload.kyc_principal
        expect(new_principal).not_to eq(registry_principal)
        expect(new_principal.name).to eq("Riley Sample")
        expect(new_principal.date_of_birth).to eq(Date.new(1990, 6, 2))
        expect(new_principal).to be_unconfirmed
        expect(new_principal).to be_unspecified
      end

      it "links the document to the new principal and clears the mismatch" do
        call(resolution: "different_person")

        expect(document.reload.match_method).to eq("exact")
        expect(document.match_confidence).to eq(1.0)
        expect(document.dob_mismatch_kyc_principal).to be_nil
      end

      it "leaves the original registry principal untouched" do
        call(resolution: "different_person")

        expect(registry_principal.reload.date_of_birth).to be_nil
        expect(registry_principal.reload).to be_confirmed
      end

      it "records an audit row referencing the original mismatched principal" do
        result = call(resolution: "different_person", reason: "Different person entirely")

        expect(result.override).to be_different_person
        expect(result.override.kyc_principal).to eq(registry_principal)
      end
    end
  end
end
