# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Kyc::EvidenceLinks", type: :request do
  let_it_be(:psp_admin)   { create(:user, :psp_admin) }
  let_it_be(:psp_support) { create(:user, :psp_support) }

  let_it_be(:applicant) { create(:applicant) }
  let_it_be(:domain)    { create(:applicant_domain, applicant: applicant, review_status: :pending, source: :extracted) }

  let(:proof) { create(:kyc_document, applicant: applicant, document_type: :proof_of_domain_ownership) }
  let(:row_target) { ActionView::RecordIdentifier.dom_id(domain) }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }

  describe "GET /kyc/applicant_domains/:id/evidence_links/new" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "lists this applicant's unlinked proof-of-domain documents only" do
        available = proof
        linked = create(:kyc_document, applicant: applicant, document_type: :proof_of_domain_ownership)
        create(:applicant_domain_document, applicant_domain: domain, kyc_document: linked)
        passport = create(:kyc_document, applicant: applicant, document_type: :passport)
        foreign = create(:kyc_document, document_type: :proof_of_domain_ownership)

        get new_kyc_applicant_domain_evidence_link_path(domain)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(%(value="#{available.id}"))
        expect(response.body).not_to include(%(value="#{linked.id}"))
        expect(response.body).not_to include(%(value="#{passport.id}"))
        expect(response.body).not_to include(%(value="#{foreign.id}"))
      end

      it "explains when there is nothing to attach" do
        get new_kyc_applicant_domain_evidence_link_path(domain)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("No proof of domain ownership documents are available to attach")
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        get new_kyc_applicant_domain_evidence_link_path(domain)

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /kyc/applicant_domains/:id/evidence_links" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "links the document and replaces the row and clears the modal via turbo_stream" do
        expect {
          post kyc_applicant_domain_evidence_links_path(domain),
            params: { evidence_link: { kyc_document_id: proof.id } }, headers: turbo
        }.to change { domain.evidence_links.count }.by(1)

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include(%(<turbo-stream action="replace" target="#{row_target}"))
        expect(response.body).to include(%(<turbo-stream action="update" target="applicant-domain-modal"))
        expect(domain.reload.evidence_documents).to contain_exactly(proof)
      end

      it "redirects to the applicant for an html request" do
        post kyc_applicant_domain_evidence_links_path(domain),
          params: { evidence_link: { kyc_document_id: proof.id } }

        expect(response).to redirect_to(applicant_path(applicant))
      end

      it "does not change the domain's review status" do
        post kyc_applicant_domain_evidence_links_path(domain),
          params: { evidence_link: { kyc_document_id: proof.id } }, headers: turbo

        expect(domain.reload).to be_pending
      end

      it "refuses another applicant's document" do
        foreign = create(:kyc_document, document_type: :proof_of_domain_ownership)

        expect {
          post kyc_applicant_domain_evidence_links_path(domain),
            params: { evidence_link: { kyc_document_id: foreign.id } }, headers: turbo
        }.not_to change(ApplicantDomainDocument, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "refuses a document that is not a proof of domain ownership" do
        passport = create(:kyc_document, applicant: applicant, document_type: :passport)

        expect {
          post kyc_applicant_domain_evidence_links_path(domain),
            params: { evidence_link: { kyc_document_id: passport.id } }, headers: turbo
        }.not_to change(ApplicantDomainDocument, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "refuses a document that is already linked, without creating a duplicate" do
        create(:applicant_domain_document, applicant_domain: domain, kyc_document: proof)

        expect {
          post kyc_applicant_domain_evidence_links_path(domain),
            params: { evidence_link: { kyc_document_id: proof.id } }, headers: turbo
        }.not_to change(ApplicantDomainDocument, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "refuses a missing or unknown document id" do
        expect {
          post kyc_applicant_domain_evidence_links_path(domain),
            params: { evidence_link: { kyc_document_id: "" } }, headers: turbo
          post kyc_applicant_domain_evidence_links_path(domain),
            params: { evidence_link: { kyc_document_id: SecureRandom.uuid } }, headers: turbo
        }.not_to change(ApplicantDomainDocument, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403 and creates no link" do
        expect {
          post kyc_applicant_domain_evidence_links_path(domain),
            params: { evidence_link: { kyc_document_id: proof.id } }, headers: turbo
        }.not_to change(ApplicantDomainDocument, :count)

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "DELETE /kyc/evidence_links/:id" do
    let!(:link) { create(:applicant_domain_document, applicant_domain: domain, kyc_document: proof) }

    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "removes only the link and replaces the row via turbo_stream" do
        delete kyc_evidence_link_path(link), headers: turbo

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(%(<turbo-stream action="replace" target="#{row_target}"))
        expect(ApplicantDomainDocument.exists?(link.id)).to be(false)
        expect(KycDocument.exists?(proof.id)).to be(true)
        expect(ApplicantDomain.exists?(domain.id)).to be(true)
      end

      it "leaves the domain's review status alone" do
        delete kyc_evidence_link_path(link), headers: turbo

        expect(domain.reload).to be_pending
      end

      it "redirects to the applicant for an html request" do
        delete kyc_evidence_link_path(link)

        expect(response).to redirect_to(applicant_path(applicant))
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403 and keeps the link" do
        delete kyc_evidence_link_path(link), headers: turbo

        expect(response).to have_http_status(:forbidden)
        expect(ApplicantDomainDocument.exists?(link.id)).to be(true)
      end
    end
  end
end
