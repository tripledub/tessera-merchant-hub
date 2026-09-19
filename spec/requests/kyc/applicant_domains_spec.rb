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

  describe "POST create (review state)" do
    before { sign_in psp_admin }

    it "creates a hand-added domain as accepted and manual, needing no review" do
      post applicant_kyc_applicant_domains_path(applicant), params: {
        applicant_domain: { name: "handadded.com" }
      }

      created = applicant.applicant_domains.find_by!(name: "handadded.com")
      expect(created).to be_accepted
      expect(created).to be_source_manual
    end

    it "ignores review_status and source smuggled into the params" do
      post applicant_kyc_applicant_domains_path(applicant), params: {
        applicant_domain: { name: "sneaky.com", review_status: "pending", source: "extracted" }
      }

      created = applicant.applicant_domains.find_by!(name: "sneaky.com")
      expect(created).to be_accepted
      expect(created).to be_source_manual
    end
  end

  describe "PATCH /kyc_applicant_domains/:id/accept and /reject" do
    let(:source_document) { create(:kyc_document, applicant: applicant, document_type: :proof_of_domain_ownership) }
    let(:candidate) do
      create(:applicant_domain, applicant: applicant, review_status: :pending,
             source: :extracted, source_document: source_document)
    end

    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "accepts a pending domain and redirects to the applicant" do
        patch accept_kyc_applicant_domain_path(candidate)

        expect(response).to redirect_to(applicant_path(applicant))
        expect(candidate.reload).to be_accepted
      end

      it "rejects a pending domain and redirects to the applicant" do
        patch reject_kyc_applicant_domain_path(candidate)

        expect(response).to redirect_to(applicant_path(applicant))
        expect(candidate.reload).to be_rejected
      end

      it "re-accepts a rejected domain" do
        candidate.rejected!

        patch accept_kyc_applicant_domain_path(candidate)

        expect(candidate.reload).to be_accepted
      end

      it "can reject a previously accepted domain" do
        candidate.accepted!

        patch reject_kyc_applicant_domain_path(candidate)

        expect(candidate.reload).to be_rejected
      end

      it "replaces just the row via turbo_stream so the user stays on the Domains tab" do
        patch accept_kyc_applicant_domain_path(candidate), as: :turbo_stream

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include(%(<turbo-stream action="replace" target="#{ActionView::RecordIdentifier.dom_id(candidate)}"))
      end

      it "leaves the source document and verification status untouched" do
        patch accept_kyc_applicant_domain_path(candidate)

        candidate.reload
        expect(candidate.source_document).to eq(source_document)
        expect(candidate).to be_unverified
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403 and does not accept" do
        patch accept_kyc_applicant_domain_path(candidate)

        expect(response).to have_http_status(:forbidden)
        expect(candidate.reload).to be_pending
      end

      it "returns 403 and does not reject" do
        patch reject_kyc_applicant_domain_path(candidate)

        expect(response).to have_http_status(:forbidden)
        expect(candidate.reload).to be_pending
      end
    end
  end

  describe "Domains tab review UI" do
    let(:source_document) do
      create(:kyc_document, applicant: applicant, document_type: :proof_of_domain_ownership)
    end
    let!(:pending_domain) do
      create(:applicant_domain, applicant: applicant, name: "pending-shop.com", review_status: :pending,
             source: :extracted, source_document: source_document)
    end
    let!(:rejected_domain) do
      create(:applicant_domain, applicant: applicant, name: "godaddy-ish.com", review_status: :rejected,
             source: :extracted, source_document: source_document)
    end

    def domains_tab
      get tab_applicant_path(applicant, tab: "domains")
      response.body
    end

    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "shows review status and the source document for extracted domains" do
        body = domains_tab

        expect(body).to include("pending-shop.com")
        expect(body).to include("Pending review")
        expect(body).to include("Rejected")
        expect(body).to include(source_document.file.filename.to_s)
      end

      it "offers accept and reject on a pending row, and only re-accept on a rejected row" do
        body = domains_tab

        expect(body).to include(accept_kyc_applicant_domain_path(pending_domain))
        expect(body).to include(reject_kyc_applicant_domain_path(pending_domain))
        expect(body).to include(accept_kyc_applicant_domain_path(rejected_domain))
        expect(body).not_to include(reject_kyc_applicant_domain_path(rejected_domain))
      end

      it "shows no review actions on a hand-added accepted row" do
        body = domains_tab

        expect(body).not_to include(accept_kyc_applicant_domain_path(domain))
        expect(body).not_to include(reject_kyc_applicant_domain_path(domain))
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "shows review status but no accept or reject actions" do
        body = domains_tab

        expect(body).to include("Pending review")
        expect(body).not_to include(accept_kyc_applicant_domain_path(pending_domain))
        expect(body).not_to include(reject_kyc_applicant_domain_path(pending_domain))
        expect(body).not_to include(accept_kyc_applicant_domain_path(rejected_domain))
      end
    end

    it "copes with an extracted domain whose source document has since been deleted" do
      sign_in psp_admin
      source_document.destroy!

      body = domains_tab

      expect(body).to include("pending-shop.com")
      expect(pending_domain.reload.source_document).to be_nil
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
