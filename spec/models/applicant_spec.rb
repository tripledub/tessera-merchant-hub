# frozen_string_literal: true

require "rails_helper"

RSpec.describe Applicant, type: :model do
  subject(:applicant) { build(:applicant) }

  it { is_expected.to validate_presence_of(:name) }

  it "is a Merchant subclass" do
    expect(described_class.superclass).to eq(Merchant)
  end

  it "does not require merchant_id" do
    applicant.merchant_id = nil
    expect(applicant).to be_valid
  end

  it "rejects a merchant_id if set" do
    applicant.merchant_id = "merch_123"
    expect(applicant).not_to be_valid
    expect(applicant.errors[:merchant_id]).not_to be_empty
  end

  it "has many kyc_principals" do
    expect(applicant).to have_many(:kyc_principals)
      .with_foreign_key(:applicant_id)
      .dependent(:destroy)
  end

  it "has many kyc_documents" do
    expect(applicant).to have_many(:kyc_documents)
      .with_foreign_key(:applicant_id)
      .dependent(:destroy)
  end

  it "defaults status to pending" do
    expect(applicant.status).to eq("pending")
  end

  it "uses id as to_param" do
    saved = create(:applicant)
    expect(saved.to_param).to eq(saved.id)
  end
end
