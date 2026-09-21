# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::AcceptDomain, type: :service do
  let(:reviewer)  { create(:user, :psp_admin) }
  let(:applicant) { create(:applicant) }
  let(:domain)    { create(:applicant_domain, applicant: applicant, review_status: :pending, source: :extracted) }

  def call(comment_body: nil)
    described_class.call(domain: domain, reviewer: reviewer, comment_body: comment_body)
  end

  def add_evidence
    document = create(:kyc_document, applicant: applicant, document_type: :proof_of_domain_ownership)
    create(:applicant_domain_document, applicant_domain: domain, kyc_document: document)
  end

  context "when the domain has evidence" do
    before { add_evidence }

    it "accepts it without a comment" do
      expect(call).to be(true)

      expect(domain.reload).to be_accepted
      expect(domain.comments).to be_empty
    end

    it "still records a comment if one is given" do
      call(comment_body: "Checked the invoice as well.")

      expect(domain.reload).to be_accepted
      expect(domain.comments.map(&:body)).to eq([ "Checked the invoice as well." ])
    end
  end

  context "when the domain has no evidence" do
    it "refuses to accept without a comment, and says why" do
      expect(call).to be(false)

      expect(domain.reload).to be_pending
      expect(domain.comments).to be_empty
      expect(domain.errors[:base]).to include(I18n.t("kyc.applicant_domains.accept_form.comment_required"))
    end

    it "treats a blank or whitespace-only comment as no comment" do
      expect(call(comment_body: "   \n ")).to be(false)

      expect(domain.reload).to be_pending
    end

    it "accepts with a comment and records who said what" do
      expect(call(comment_body: "  Confirmed with the client by phone.  ")).to be(true)

      expect(domain.reload).to be_accepted
      comment = domain.comments.sole
      expect(comment.body).to eq("Confirmed with the client by phone.")
      expect(comment.author).to eq(reviewer)
      expect(comment.commentable).to eq(domain)
    end

    it "also requires a comment to re-accept a rejected domain" do
      domain.rejected!

      expect(call).to be(false)
      expect(domain.reload).to be_rejected

      expect(call(comment_body: "Rejected in error.")).to be(true)
      expect(domain.reload).to be_accepted
    end

    it "does not need evidence on other domains of the same applicant" do
      other = create(:applicant_domain, applicant: applicant, review_status: :pending)
      document = create(:kyc_document, applicant: applicant, document_type: :proof_of_domain_ownership)
      create(:applicant_domain_document, applicant_domain: other, kyc_document: document)

      expect(call).to be(false)
    end
  end

  it "does not leave a comment behind if the acceptance itself fails" do
    allow(domain).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(domain))

    expect { call(comment_body: "Reason.") }.to raise_error(ActiveRecord::RecordInvalid)

    expect(Comment.count).to eq(0)
  end
end
