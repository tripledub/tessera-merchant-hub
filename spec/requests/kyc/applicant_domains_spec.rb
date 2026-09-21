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
      create(:applicant_domain, applicant: applicant, review_status: :pending, source: :extracted).tap do |d|
        create(:applicant_domain_document, applicant_domain: d, kyc_document: source_document)
      end
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

      it "leaves the evidence and verification status untouched" do
        patch accept_kyc_applicant_domain_path(candidate)

        candidate.reload
        expect(candidate.evidence_documents).to contain_exactly(source_document)
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
             source: :extracted).tap do |d|
        create(:applicant_domain_document, applicant_domain: d, kyc_document: source_document)
      end
    end
    let!(:rejected_domain) do
      create(:applicant_domain, applicant: applicant, name: "godaddy-ish.com", review_status: :rejected,
             source: :extracted).tap do |d|
        create(:applicant_domain_document, applicant_domain: d, kyc_document: source_document)
      end
    end

    def domains_tab
      get tab_applicant_path(applicant, tab: "domains")
      response.body
    end

    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "shows review status and the evidence document for extracted domains" do
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

    it "keeps a domain when its only evidence document is deleted, and says so" do
      sign_in psp_admin
      source_document.destroy!

      body = domains_tab

      expect(body).to include("pending-shop.com")
      expect(body).to include("No evidence on file")
      expect(pending_domain.reload.evidence_documents).to be_empty
      expect(pending_domain).to be_pending
    end

    describe "evidence column" do
      def proof_document(filename:, content_type: "application/pdf")
        create(:kyc_document, applicant: applicant, document_type: :proof_of_domain_ownership).tap do |doc|
          doc.file.attach(io: StringIO.new("x"), filename: filename, content_type: content_type)
        end
      end

      it "lists every evidence document for a domain" do
        sign_in psp_admin
        create(:applicant_domain_document, applicant_domain: pending_domain,
               kyc_document: proof_document(filename: "second-invoice.pdf"))

        body = domains_tab

        expect(body).to include("second-invoice.pdf")
        expect(body).to include(source_document.file.filename.to_s)
      end

      it "makes an image or PDF a button that opens the document preview" do
        sign_in psp_admin

        body = domains_tab

        expect(body).to include(%(data-controller="document-preview"))
        expect(body).to include(%(data-document-preview-content-type-value="application/pdf"))
        expect(body).to include(%(data-document-preview-url-value="#{rails_blob_path(source_document.file, only_path: true, disposition: :inline)}"))
      end

      it "shows a spreadsheet or CSV as plain text with no preview button" do
        sign_in psp_admin
        csv_domain = create(:applicant_domain, applicant: applicant, name: "csv-evidence.com")
        create(:applicant_domain_document, applicant_domain: csv_domain,
               kyc_document: proof_document(filename: "domains-export.csv", content_type: "text/csv"))

        body = domains_tab

        expect(body).to include("domains-export.csv")
        expect(body).not_to include(%(data-document-preview-content-type-value="text/csv"))
      end

      it "says there is no evidence for a hand-added domain with none" do
        sign_in psp_admin

        expect(domains_tab).to include("No evidence on file")
      end

      it "offers add and unlink evidence actions to a psp_admin" do
        sign_in psp_admin
        link = pending_domain.evidence_links.first

        body = domains_tab

        expect(body).to include(new_kyc_applicant_domain_evidence_link_path(pending_domain))
        expect(body).to include(new_kyc_applicant_domain_evidence_link_path(domain))
        expect(body).to include(kyc_evidence_link_path(link))
      end

      it "shows a psp_support user the evidence and preview but no add or unlink actions" do
        sign_in psp_support
        link = pending_domain.evidence_links.first

        body = domains_tab

        expect(body).to include(source_document.file.filename.to_s)
        expect(body).to include(%(data-controller="document-preview"))
        expect(body).not_to include(new_kyc_applicant_domain_evidence_link_path(pending_domain))
        expect(body).not_to include(kyc_evidence_link_path(link))
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
