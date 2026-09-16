# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicantDomain, type: :model do
  subject(:applicant_domain) { build(:applicant_domain) }

  it { is_expected.to belong_to(:applicant) }
  it { is_expected.to have_many(:kyc_documents).dependent(:nullify) }

  it "defaults verification_status to unverified" do
    expect(applicant_domain.verification_status).to eq("unverified")
  end

  it "defines the verification_status enum" do
    expect(described_class.verification_statuses).to eq(
      "unverified" => 0,
      "verified" => 1
    )
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
