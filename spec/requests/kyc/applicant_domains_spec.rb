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

  describe "GET /applicants/:applicant_id/kyc_applicant_domains/new (justification)" do
    it "asks the psp_admin why the domain is trusted" do
      sign_in psp_admin

      get new_applicant_kyc_applicant_domain_path(applicant)

      expect(response.body).to include("applicant_domain[justification]")
      expect(response.body).to include("Why is this domain trusted?")
    end
  end

  describe "POST /applicants/:applicant_id/kyc_applicant_domains" do
    let(:reason) { "Client showed us the registrar account." }

    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "creates the domain and redirects to applicant" do
        post applicant_kyc_applicant_domains_path(applicant), params: {
          applicant_domain: { name: "newdomain.com", justification: reason }
        }
        expect(response).to redirect_to(applicant_path(applicant))
        expect(applicant.applicant_domains.find_by(name: "newdomain.com")).to be_present
      end

      it "stores the justification as a comment by the person adding it" do
        post applicant_kyc_applicant_domains_path(applicant), params: {
          applicant_domain: { name: "newdomain.com", justification: reason }
        }

        comment = applicant.applicant_domains.find_by!(name: "newdomain.com").comments.sole
        expect(comment.body).to eq(reason)
        expect(comment.author).to eq(psp_admin)
      end

      it "re-renders new with 422 on an invalid domain, creating nothing" do
        expect {
          post applicant_kyc_applicant_domains_path(applicant), params: {
            applicant_domain: { name: "not a domain", justification: reason }
          }
        }.not_to change { [ ApplicantDomain.count, Comment.count ] }

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "refuses a domain with no justification: 422, no domain, no comment" do
        expect {
          post applicant_kyc_applicant_domains_path(applicant), params: {
            applicant_domain: { name: "unjustified.com", justification: "  " }
          }
        }.not_to change { [ ApplicantDomain.count, Comment.count ] }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Reason can&#39;t be blank")
      end

      it "keeps what was typed when it re-renders" do
        post applicant_kyc_applicant_domains_path(applicant), params: {
          applicant_domain: { name: "keepme.com", justification: "" }
        }

        expect(response.body).to include("keepme.com")
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403 and creates nothing" do
        expect {
          post applicant_kyc_applicant_domains_path(applicant), params: {
            applicant_domain: { name: "newdomain.com", justification: reason }
          }
        }.not_to change { [ ApplicantDomain.count, Comment.count ] }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST create (review state)" do
    before { sign_in psp_admin }

    it "creates a hand-added domain as accepted and manual, needing no review" do
      post applicant_kyc_applicant_domains_path(applicant), params: {
        applicant_domain: { name: "handadded.com", justification: "Seen it." }
      }

      created = applicant.applicant_domains.find_by!(name: "handadded.com")
      expect(created).to be_accepted
      expect(created).to be_source_manual
    end

    it "ignores review_status and source smuggled into the params" do
      post applicant_kyc_applicant_domains_path(applicant), params: {
        applicant_domain: { name: "sneaky.com", justification: "Seen it.", review_status: "pending", source: "extracted" }
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

  # MH-300: accepting a domain that has no evidence document needs a comment.
  describe "accepting a domain with no evidence" do
    let(:bare) { create(:applicant_domain, applicant: applicant, review_status: :pending, source: :extracted) }
    let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }
    let(:reason) { "Confirmed with the client by phone." }

    def evidence_for(domain)
      document = create(:kyc_document, applicant: applicant, document_type: :proof_of_domain_ownership)
      create(:applicant_domain_document, applicant_domain: domain, kyc_document: document)
    end

    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "opens a form asking for the comment" do
        get accept_form_kyc_applicant_domain_path(bare)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(bare.name)
        expect(response.body).to include("comment[body]")
        expect(response.body).to include(accept_kyc_applicant_domain_path(bare))
      end

      it "refuses without a comment: 422, still pending, no comment, and says why" do
        expect {
          patch accept_kyc_applicant_domain_path(bare), headers: turbo
        }.not_to change(Comment, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(bare.reload).to be_pending
        expect(response.body).to include(I18n.t("kyc.applicant_domains.accept_form.comment_required"))
      end

      it "refuses a whitespace-only comment" do
        patch accept_kyc_applicant_domain_path(bare), params: { comment: { body: "  " } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(bare.reload).to be_pending
      end

      it "accepts with a comment and records the author" do
        patch accept_kyc_applicant_domain_path(bare), params: { comment: { body: reason } }

        expect(response).to redirect_to(applicant_path(applicant))
        expect(bare.reload).to be_accepted
        comment = bare.comments.sole
        expect(comment.body).to eq(reason)
        expect(comment.author).to eq(psp_admin)
      end

      it "replaces the row and clears the modal via turbo_stream" do
        patch accept_kyc_applicant_domain_path(bare), params: { comment: { body: reason } }, headers: turbo

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(%(<turbo-stream action="replace" target="#{ActionView::RecordIdentifier.dom_id(bare)}"))
        expect(response.body).to include(%(<turbo-stream action="update" target="applicant-domain-modal"))
        expect(response.body).to include(reason)
      end

      it "also needs a comment to re-accept a rejected domain" do
        bare.rejected!

        patch accept_kyc_applicant_domain_path(bare)
        expect(response).to have_http_status(:unprocessable_content)
        expect(bare.reload).to be_rejected

        patch accept_kyc_applicant_domain_path(bare), params: { comment: { body: "Rejected in error." } }
        expect(bare.reload).to be_accepted
      end

      it "needs no comment when the domain has evidence" do
        evidence_for(bare)

        expect {
          patch accept_kyc_applicant_domain_path(bare)
        }.not_to change(Comment, :count)

        expect(bare.reload).to be_accepted
      end

      it "never needs a comment to reject" do
        patch reject_kyc_applicant_domain_path(bare)

        expect(response).to redirect_to(applicant_path(applicant))
        expect(bare.reload).to be_rejected
      end

      it "leaves an accepted domain accepted when its evidence is removed later" do
        link = evidence_for(bare)
        patch accept_kyc_applicant_domain_path(bare)

        delete kyc_evidence_link_path(link), headers: turbo

        expect(bare.reload).to be_accepted
        expect(bare.evidence_links).to be_empty
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "cannot open the form" do
        get accept_form_kyc_applicant_domain_path(bare)

        expect(response).to have_http_status(:forbidden)
      end

      it "cannot accept, even with a comment, and no comment is recorded" do
        expect {
          patch accept_kyc_applicant_domain_path(bare), params: { comment: { body: reason } }
        }.not_to change(Comment, :count)

        expect(response).to have_http_status(:forbidden)
        expect(bare.reload).to be_pending
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

    describe "blocklisted rejections (MH-298)" do
      it "tags a domain the blocklist rejected, and only that one" do
        sign_in psp_admin
        create(:applicant_domain, applicant: applicant, name: "listed-registrar.com",
               review_status: :rejected, rejection_reason: :blocklisted, source: :extracted)

        body = domains_tab
        tag = I18n.t("kyc.applicant_domains.rejection_reason.blocklisted")

        expect(body).to include("listed-registrar.com")
        expect(body.scan(tag).size).to eq(1) # rejected_domain, rejected by hand, is not tagged
      end
    end

    describe "accept control and reviewer note (MH-300)" do
      let!(:bare_pending) do
        create(:applicant_domain, applicant: applicant, name: "no-evidence.com", review_status: :pending, source: :extracted)
      end

      it "sends a psp_admin to the comment form to accept a domain with no evidence, and one click when it has evidence" do
        sign_in psp_admin

        body = domains_tab

        # "/accept" is a prefix of "/accept_form", so match the one-click form's exact action.
        one_click = ->(domain) { %(action="#{accept_kyc_applicant_domain_path(domain)}") }

        expect(body).to include(accept_form_kyc_applicant_domain_path(bare_pending))
        expect(body).not_to include(one_click.call(bare_pending))
        expect(body).to include(one_click.call(pending_domain))
        expect(body).not_to include(accept_form_kyc_applicant_domain_path(pending_domain))
      end

      it "shows the most recent reviewer note with its author and date" do
        sign_in psp_admin
        create(:comment, commentable: bare_pending, author: psp_admin, body: "First thought.", created_at: 2.days.ago)
        create(:comment, commentable: bare_pending, author: psp_support, body: "Verified by phone.", created_at: 1.day.ago)

        body = domains_tab

        expect(body).to include("Verified by phone.")
        expect(body).to include(psp_support.email)
        expect(body).not_to include("First thought.")
      end

      it "lets a psp_support user read the note but not act on it" do
        sign_in psp_support
        create(:comment, commentable: bare_pending, author: psp_admin, body: "Verified by phone.")

        body = domains_tab

        expect(body).to include("Verified by phone.")
        expect(body).not_to include(accept_form_kyc_applicant_domain_path(bare_pending))
      end

      it "shows no note for a domain nobody has commented on" do
        sign_in psp_admin

        expect(domains_tab).not_to include(I18n.t("kyc.applicant_domains.note.label"))
      end

      it "escapes the note, since it is free text" do
        sign_in psp_admin
        create(:comment, commentable: bare_pending, author: psp_admin, body: "<script>alert(1)</script>")

        body = domains_tab

        expect(body).not_to include("<script>alert(1)</script>")
        expect(body).to include("&lt;script&gt;")
      end
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
