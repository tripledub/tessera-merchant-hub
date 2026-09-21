# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::DomainEvidenceRecorder, type: :service do
  let(:applicant) { create(:applicant) }
  let(:document) do
    create(:kyc_document, applicant: applicant, document_type: :proof_of_domain_ownership)
  end

  def call(names, doc: document)
    described_class.call(document: doc, names: names)
  end

  it "creates a pending, extracted domain linked to the document for a new name" do
    expect { call(%w[example.com]) }.to change { applicant.applicant_domains.count }.by(1)

    domain = applicant.applicant_domains.find_by!(name: "example.com")
    expect(domain).to be_pending
    expect(domain).to be_source_extracted
    expect(domain.evidence_documents).to contain_exactly(document)
  end

  it "handles several names in one call" do
    call(%w[example.com other-site.net])

    expect(applicant.applicant_domains.pluck(:name)).to match_array(%w[example.com other-site.net])
    expect(ApplicantDomainDocument.where(kyc_document_id: document.id).count).to eq(2)
  end

  context "when the applicant already has the domain" do
    it "links the document as evidence without touching a hand-added, accepted domain" do
      existing = create(:applicant_domain, applicant: applicant, name: "Example.com")

      expect { call(%w[example.com]) }.not_to change { applicant.applicant_domains.count }

      existing.reload
      expect(existing).to be_accepted
      expect(existing).to be_source_manual
      expect(existing.evidence_documents).to contain_exactly(document)
    end

    it "links the document to a rejected domain and leaves it rejected" do
      rejected = create(:applicant_domain, applicant: applicant, name: "example.com", review_status: :rejected)

      call(%w[example.com])

      expect(rejected.reload).to be_rejected
      expect(rejected.evidence_documents).to contain_exactly(document)
    end

    it "links the document to a pending domain and leaves it pending" do
      pending_domain = create(:applicant_domain, applicant: applicant, name: "example.com", review_status: :pending)

      call(%w[example.com])

      expect(pending_domain.reload).to be_pending
      expect(pending_domain.evidence_documents).to contain_exactly(document)
    end
  end

  it "accumulates evidence: a second document adds a link, not a duplicate domain" do
    second = create(:kyc_document, applicant: applicant, document_type: :proof_of_domain_ownership)
    call(%w[example.com])

    expect { call(%w[example.com], doc: second) }.not_to change { applicant.applicant_domains.count }

    expect(applicant.applicant_domains.find_by!(name: "example.com").evidence_documents)
      .to contain_exactly(document, second)
  end

  it "is idempotent when the same document is recorded twice" do
    call(%w[example.com])

    expect { call(%w[example.com]) }.not_to change(ApplicantDomainDocument, :count)
  end

  it "does not touch another applicant's domain of the same name" do
    other = create(:applicant_domain, name: "example.com")

    call(%w[example.com])

    expect(other.reload.evidence_documents).to be_empty
    expect(applicant.applicant_domains.find_by!(name: "example.com")).not_to eq(other)
  end

  it "skips a name that is not a valid domain rather than failing the run" do
    expect { call([ "not a domain", "example.com" ]) }.not_to raise_error

    expect(applicant.applicant_domains.pluck(:name)).to eq(%w[example.com])
  end

  it "does nothing for an empty list" do
    expect { call([]) }.not_to change(ApplicantDomainDocument, :count)
  end
end
