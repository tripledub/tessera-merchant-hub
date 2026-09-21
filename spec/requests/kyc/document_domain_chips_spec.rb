# frozen_string_literal: true

require "rails_helper"

# MH-299: since the per-document domain dropdown was removed (MH-296), a
# proof-of-domain row on the Documents tab shows which domains it evidences.
RSpec.describe "Documents tab domain chips", type: :request do
  let_it_be(:psp_admin)   { create(:user, :psp_admin) }
  let_it_be(:psp_support) { create(:user, :psp_support) }
  let_it_be(:applicant)   { create(:applicant) }

  def documents_tab
    get tab_applicant_path(applicant, tab: "documents")
    response.body
  end

  def link(document, name, review_status: :accepted)
    domain = applicant.applicant_domains.find_by(name: name) ||
      create(:applicant_domain, applicant: applicant, name: name, review_status: review_status)
    create(:applicant_domain_document, applicant_domain: domain, kyc_document: document)
    domain
  end

  let(:proof) { create(:kyc_document, applicant: applicant, document_type: :proof_of_domain_ownership) }

  context "when signed in as psp_admin" do
    before { sign_in psp_admin }

    it "lists the domains linked to a proof-of-domain document with their review status" do
      link(proof, "chip-accepted.com", review_status: :accepted)
      link(proof, "chip-pending.com", review_status: :pending)
      link(proof, "chip-rejected.com", review_status: :rejected)

      body = documents_tab

      expect(body).to include("chip-accepted.com", "chip-pending.com", "chip-rejected.com")
      expect(body).to include("Accepted", "Pending review", "Rejected")
    end

    it "is read-only: no accept, reject or unlink controls on the Documents tab" do
      domain = link(proof, "readonly-chip.com", review_status: :pending)

      body = documents_tab

      expect(body).not_to include(accept_kyc_applicant_domain_path(domain))
      expect(body).not_to include(reject_kyc_applicant_domain_path(domain))
      expect(body).not_to include(kyc_evidence_link_path(domain.evidence_links.first))
    end

    it "shows a domain against every document that evidences it" do
      other = create(:kyc_document, applicant: applicant, document_type: :proof_of_domain_ownership)
      link(proof, "shared-chip.com")
      link(other, "shared-chip.com")

      expect(documents_tab.scan("shared-chip.com").size).to eq(2)
    end

    it "shows no domains section for a proof-of-domain document with no links" do
      proof

      expect(documents_tab).not_to include(I18n.t("kyc.documents.evidenced_domains"))
    end

    it "does not fire a domain query per document" do
      3.times do |i|
        doc = create(:kyc_document, applicant: applicant, document_type: :proof_of_domain_ownership)
        link(doc, "n-plus-one-#{i}.com")
      end

      domain_queries = []
      callback = lambda do |*, payload|
        domain_queries << payload[:sql] if payload[:sql].match?(/FROM "applicant_domains"/) && payload[:name] != "SCHEMA"
      end
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { documents_tab }

      expect(domain_queries.size).to be <= 2
    end
  end

  context "when signed in as psp_support" do
    before { sign_in psp_support }

    it "can see the linked domains" do
      link(proof, "support-chip.com")

      expect(documents_tab).to include("support-chip.com")
    end
  end
end
