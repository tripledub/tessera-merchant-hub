# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicantDomain, type: :model do
  subject(:applicant_domain) { build(:applicant_domain) }

  it { is_expected.to belong_to(:applicant) }
  it { expect(described_class.reflect_on_association(:kyc_documents)).to be_nil }

  it "defaults verification_status to unverified" do
    expect(applicant_domain.verification_status).to eq("unverified")
  end

  it "defines the verification_status enum" do
    expect(described_class.verification_statuses).to eq(
      "unverified" => 0,
      "verified" => 1
    )
  end

  it "defaults review_status to accepted so hand-added domains need no review" do
    expect(applicant_domain.review_status).to eq("accepted")
  end

  it "defines the review_status enum" do
    expect(described_class.review_statuses).to eq(
      "pending" => 0,
      "accepted" => 1,
      "rejected" => 2
    )
  end

  it "defaults source to manual" do
    expect(applicant_domain.source).to eq("manual")
  end

  it "defines the source enum" do
    expect(described_class.sources).to eq("manual" => 0, "extracted" => 1)
  end

  it { is_expected.to have_many(:comments).dependent(:delete_all) }

  it "carries a justification for the Add domain form without persisting it as a column" do
    applicant_domain.justification = "Seen the registrar account."

    expect(applicant_domain.justification).to eq("Seen the registrar account.")
    expect(described_class.column_names).not_to include("justification")
  end

  it "removes its comments when destroyed" do
    domain = create(:applicant_domain)
    create(:comment, commentable: domain)

    expect { domain.destroy! }.to change(Comment, :count).by(-1)
  end

  it { is_expected.to have_many(:evidence_links).class_name("ApplicantDomainDocument").dependent(:delete_all) }
  it { is_expected.to have_many(:evidence_documents).through(:evidence_links).source(:kyc_document) }

  it "no longer records a single source document (MH-299)" do
    expect(described_class.column_names).not_to include("source_document_id")
    expect(described_class.reflect_on_association(:source_document)).to be_nil
  end

  it "removes its evidence links but not the documents when destroyed" do
    link = create(:applicant_domain_document)

    link.applicant_domain.destroy!

    expect(described_class.exists?(link.applicant_domain_id)).to be(false)
    expect(ApplicantDomainDocument.exists?(link.id)).to be(false)
    expect(KycDocument.exists?(link.kyc_document_id)).to be(true)
  end

  it { is_expected.to validate_presence_of(:name) }

  it "accepts a plain domain name" do
    applicant_domain.name = "example.com"
    expect(applicant_domain).to be_valid
  end

  it "accepts a subdomain" do
    applicant_domain.name = "www.example.co.uk"
    expect(applicant_domain).to be_valid
  end

  it "rejects a value with no TLD" do
    applicant_domain.name = "example"
    expect(applicant_domain).not_to be_valid
    expect(applicant_domain.errors[:name]).not_to be_empty
  end

  it "rejects a value containing spaces" do
    applicant_domain.name = "not a domain.com"
    expect(applicant_domain).not_to be_valid
  end

  it "rejects a full URL rather than a bare domain" do
    applicant_domain.name = "https://example.com"
    expect(applicant_domain).not_to be_valid
  end

  it "prevents duplicate domains (case-insensitive) for the same applicant" do
    applicant = create(:applicant)
    create(:applicant_domain, applicant: applicant, name: "example.com")

    duplicate = build(:applicant_domain, applicant: applicant, name: "EXAMPLE.com")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:name]).to include("has already been taken")
  end

  it "enforces the uniqueness constraint at the database level" do
    applicant = create(:applicant)
    create(:applicant_domain, applicant: applicant, name: "example.com")
    now = Time.current

    expect {
      described_class.insert_all!([
        {
          applicant_id: applicant.id,
          name: "EXAMPLE.com",
          verification_status: 0,
          created_at: now,
          updated_at: now
        }
      ])
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "allows the same domain name for different applicants" do
    create(:applicant_domain, name: "example.com")
    other = build(:applicant_domain, name: "example.com")

    expect(other).to be_valid
  end
end
