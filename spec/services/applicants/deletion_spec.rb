# frozen_string_literal: true

require "rails_helper"

RSpec.describe Applicants::Deletion, type: :service do
  describe ".call" do
    context "when the applicant has no portal user" do
      let(:applicant) { create(:applicant) }
      let!(:kyc_document) { create(:kyc_document, applicant: applicant) }
      let!(:kyc_principal) { create(:kyc_principal, applicant: applicant) }
      let!(:corporate_entity) { create(:kyc_corporate_entity, applicant: applicant, kyc_document: kyc_document) }
      let!(:validation_warning) do
        create(:kyc_validation_warning, applicant: applicant, kyc_document: kyc_document, corporate_entity: corporate_entity)
      end
      let!(:onboarding_session) { create(:onboarding_session, applicant: applicant) }

      it "destroys the applicant and its associated records" do
        described_class.call(applicant)

        expect(Applicant.find_by(id: applicant.id)).to be_nil
        expect(KycDocument.find_by(id: kyc_document.id)).to be_nil
        expect(KycPrincipal.find_by(id: kyc_principal.id)).to be_nil
        expect(Kyc::CorporateEntity.find_by(id: corporate_entity.id)).to be_nil
        expect(Kyc::ValidationWarning.find_by(id: validation_warning.id)).to be_nil
        expect(OnboardingSession.find_by(id: onboarding_session.id)).to be_nil
      end

      it "enqueues a purge job for each attached KYC document file" do
        blob = kyc_document.file.blob

        expect { described_class.call(applicant) }
          .to have_enqueued_job(ActiveStorage::PurgeJob).with(blob)
      end

      it "returns the applicant with no errors" do
        result = described_class.call(applicant)
        expect(result.errors).to be_empty
      end
    end

    context "when the applicant has an associated portal user" do
      let(:applicant) { create(:applicant) }
      let!(:applicant_user) { create(:applicant_user, applicant: applicant) }
      let!(:kyc_document) { create(:kyc_document, applicant: applicant) }

      it "does not destroy the applicant or its associated records" do
        described_class.call(applicant)

        expect(Applicant.find_by(id: applicant.id)).to be_present
        expect(KycDocument.find_by(id: kyc_document.id)).to be_present
      end

      it "does not enqueue any purge jobs" do
        expect { described_class.call(applicant) }
          .not_to have_enqueued_job(ActiveStorage::PurgeJob)
      end

      it "returns the applicant with a base error" do
        result = described_class.call(applicant)
        expect(result.errors[:base]).to include(
          "Cannot delete an applicant with an active portal user account"
        )
      end
    end
  end
end
