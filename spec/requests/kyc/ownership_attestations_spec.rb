# frozen_string_literal: true

require "rails_helper"

# MH-251: staff can attest an applicant has no corporate owners, which is the
# only way an empty ownership graph can be compliant.
RSpec.describe "OwnershipAttestations", type: :request do
  let_it_be(:psp_admin)   { create(:user, :psp_admin) }
  let_it_be(:psp_support) { create(:user, :psp_support) }

  let(:applicant) { create(:applicant) }

  describe "POST /applicants/:applicant_id/kyc/ownership_attestation" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "records who attested and when, then returns to the applicant" do
        post applicant_kyc_ownership_attestation_path(applicant)

        expect(response).to redirect_to(applicant_path(applicant))
        applicant.reload
        expect(applicant).to be_no_corporate_owners_attested
        expect(applicant.no_corporate_owners_attested_by).to eq(psp_admin)
      end

      it "refuses to attest once ownership entities have been captured" do
        create(:kyc_corporate_entity, applicant: applicant, kyc_document: create(:kyc_document, applicant: applicant))

        post applicant_kyc_ownership_attestation_path(applicant)

        expect(response).to redirect_to(applicant_path(applicant))
        expect(flash[:alert]).to be_present
        expect(applicant.reload).not_to be_no_corporate_owners_attested
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403 and records nothing" do
        post applicant_kyc_ownership_attestation_path(applicant)

        expect(response).to have_http_status(:forbidden)
        expect(applicant.reload).not_to be_no_corporate_owners_attested
      end
    end

    it "requires sign-in" do
      post applicant_kyc_ownership_attestation_path(applicant)

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "DELETE /applicants/:applicant_id/kyc/ownership_attestation" do
    before { applicant.attest_no_corporate_owners!(by: psp_admin) }

    it "removes the attestation for psp_admin" do
      sign_in psp_admin

      delete applicant_kyc_ownership_attestation_path(applicant)

      expect(response).to redirect_to(applicant_path(applicant))
      expect(applicant.reload).not_to be_no_corporate_owners_attested
    end

    it "returns 403 for psp_support and keeps the attestation" do
      sign_in psp_support

      delete applicant_kyc_ownership_attestation_path(applicant)

      expect(response).to have_http_status(:forbidden)
      expect(applicant.reload).to be_no_corporate_owners_attested
    end
  end

  describe "readiness card on the overview tab" do
    it "renders the not-assessable state instead of hiding the card when nothing has been evaluated" do
      sign_in psp_admin

      get tab_applicant_path(applicant, tab: "overview")

      expect(response.body).to include("Compliance Readiness", "Not Assessable")
      expect(response.body).to include("Confirm no corporate owners")
    end

    it "hides the attestation control from psp_support" do
      sign_in psp_support

      get tab_applicant_path(applicant, tab: "overview")

      expect(response.body).to include("Not Assessable")
      expect(response.body).not_to include("Confirm no corporate owners")
    end

    it "shows who attested, and lets a psp_admin remove it" do
      applicant.attest_no_corporate_owners!(by: psp_admin)
      sign_in psp_admin

      get tab_applicant_path(applicant, tab: "overview")

      expect(response.body).to include(psp_admin.email, "Remove confirmation")
      expect(response.body).not_to include("Not Assessable")
    end
  end

  describe "readiness on the summary tab" do
    it "agrees with the overview card for the same applicant" do
      sign_in psp_admin

      get tab_applicant_path(applicant, tab: "summary")

      expect(response.body).to include("Not Assessable")
      expect(response.body).not_to include(">Compliant<")
    end
  end
end
