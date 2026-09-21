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

  # MH-298: registrar and similar domains are auto-rejected, but stay visible.
  context "when a name is on the blocklist" do
    before { create(:domain_blocklist_entry, name: "godaddy.com") }

    it "creates it rejected as blocklisted, with the document as evidence" do
      call(%w[godaddy.com])

      domain = applicant.applicant_domains.find_by!(name: "godaddy.com")
      expect(domain).to be_rejected
      expect(domain).to be_rejected_as_blocklisted
      expect(domain).to be_source_extracted
      expect(domain.evidence_documents).to contain_exactly(document)
    end

    it "leaves the applicant's other domains pending" do
      call(%w[example.com godaddy.com])

      expect(applicant.applicant_domains.find_by!(name: "example.com")).to be_pending
      expect(applicant.applicant_domains.find_by!(name: "godaddy.com")).to be_rejected
    end

    it "does not change a domain the applicant already had, only adds the evidence" do
      existing = create(:applicant_domain, applicant: applicant, name: "godaddy.com", review_status: :pending)

      call(%w[godaddy.com])

      expect(existing.reload).to be_pending
      expect(existing.rejection_reason).to be_nil
      expect(existing.evidence_documents).to contain_exactly(document)
    end

    it "counts as reviewed, so it does not hold the completeness score down" do
      call(%w[godaddy.com])

      dimension = Kyc::CompletenessCalculator.for(applicant).dimensions.find { |d| d.key == :domain_review }
      expect([ dimension.numerator, dimension.denominator ]).to eq([ 1, 1 ])
    end

    it "stops applying once the entry is removed, leaving rows already created alone" do
      call(%w[godaddy.com])
      DomainBlocklistEntry.find_by!(name: "godaddy.com").destroy!
      later = create(:kyc_document, applicant: applicant, document_type: :proof_of_domain_ownership)

      call(%w[godaddy.com other-site.net], doc: later)

      expect(applicant.applicant_domains.find_by!(name: "godaddy.com")).to be_rejected_as_blocklisted
      expect(applicant.applicant_domains.find_by!(name: "other-site.net")).to be_pending
    end
  end

  it "does not touch existing domains when a blocklist entry is added later" do
    existing = create(:applicant_domain, applicant: applicant, name: "godaddy.com", review_status: :pending)

    create(:domain_blocklist_entry, name: "godaddy.com")

    expect(existing.reload).to be_pending
  end
end
