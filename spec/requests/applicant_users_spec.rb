# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ApplicantUsers", type: :request do
  let_it_be(:psp_admin)      { create(:user, :psp_admin) }
  let_it_be(:psp_support)    { create(:user, :psp_support) }
  let_it_be(:merchant_admin) { create(:user, :merchant_admin) }

  describe "DELETE /applicant_users/:id" do
    let(:applicant) { create(:applicant) }
    let!(:applicant_user) { create(:applicant_user, applicant: applicant) }

    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "destroys the portal user and redirects to the applicant" do
        delete applicant_user_path(applicant_user)

        expect(response).to redirect_to(applicant_path(applicant))
        expect(ApplicantUser.find_by(id: applicant_user.id)).to be_nil
      end

      it "does not destroy the applicant itself" do
        delete applicant_user_path(applicant_user)
        expect(Applicant.find_by(id: applicant.id)).to be_present
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        delete applicant_user_path(applicant_user)
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 403" do
        delete applicant_user_path(applicant_user)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
