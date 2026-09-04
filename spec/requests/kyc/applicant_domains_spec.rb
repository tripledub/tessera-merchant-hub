# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ApplicantDomains", type: :request do
  let_it_be(:psp_admin)   { create(:user, :psp_admin) }
  let_it_be(:psp_support) { create(:user, :psp_support) }

  let_it_be(:applicant) { create(:applicant) }
  let_it_be(:domain)    { create(:applicant_domain, applicant: applicant) }

  describe "GET /applicants/:applicant_id/kyc_applicant_domains/new" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "returns 200" do
        get new_applicant_kyc_applicant_domain_path(applicant)
        expect(response).to have_http_status(:ok)
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        get new_applicant_kyc_applicant_domain_path(applicant)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /applicants/:applicant_id/kyc_applicant_domains" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "creates the domain and redirects to applicant" do
        post applicant_kyc_applicant_domains_path(applicant), params: {
          applicant_domain: { name: "newdomain.com" }
        }
        expect(response).to redirect_to(applicant_path(applicant))
        expect(applicant.applicant_domains.find_by(name: "newdomain.com")).to be_present
      end

      it "re-renders new with 422 on an invalid domain" do
        post applicant_kyc_applicant_domains_path(applicant), params: {
          applicant_domain: { name: "not a domain" }
        }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        post applicant_kyc_applicant_domains_path(applicant), params: {
          applicant_domain: { name: "newdomain.com" }
        }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "DELETE /kyc_applicant_domains/:id" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "destroys and redirects to applicant" do
        to_delete = create(:applicant_domain, applicant: applicant)
        delete kyc_applicant_domain_path(to_delete)
        expect(response).to redirect_to(applicant_path(applicant))
        expect(ApplicantDomain.find_by(id: to_delete.id)).to be_nil
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        delete kyc_applicant_domain_path(domain)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
