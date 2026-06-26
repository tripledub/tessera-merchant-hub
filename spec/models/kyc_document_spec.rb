# frozen_string_literal: true

require "rails_helper"

RSpec.describe KycDocument, type: :model do
  subject(:document) { build(:kyc_document) }

  it { is_expected.to belong_to(:applicant) }
  it { is_expected.to belong_to(:kyc_principal).optional }

  it "defaults status to pending" do
    expect(document.status).to eq("pending")
  end

  it "requires an attached file" do
    document.file = nil
    expect(document).not_to be_valid
    expect(document.errors[:file]).not_to be_empty
  end

  it "rejects files larger than the upload limit" do
    document.file.attach(
      io: StringIO.new("x" * (KycDocument::MAX_FILE_SIZE + 1)),
      filename: "large.pdf",
      content_type: "application/pdf"
    )

    expect(document).not_to be_valid
    expect(document.errors[:file]).to include("must be less than 10 MB")
  end

  it "can be assigned to a principal" do
    applicant  = create(:applicant)
    principal  = create(:kyc_principal, applicant: applicant)
    document   = build(:kyc_document, applicant: applicant, kyc_principal: principal)
    expect(document).to be_valid
  end

  it "can exist without a principal (company-level doc)" do
    document = build(:kyc_document, kyc_principal: nil)
    expect(document).to be_valid
  end
end
