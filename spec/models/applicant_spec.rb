# frozen_string_literal: true

require "rails_helper"

RSpec.describe Applicant, type: :model do
  subject(:applicant) { build(:applicant) }

  it { is_expected.to validate_presence_of(:name) }

  it "requires a unique applicant name" do
    create(:applicant, name: "Acme Ltd")

    duplicate = build(:applicant, name: "acme ltd")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:name]).to include("has already been taken")
  end

  it "enforces unique applicant names at the database level" do
    create(:applicant, name: "Acme Ltd")
    now = Time.current

    expect {
      described_class.insert_all!([
        {
          type: "Applicant",
          name: "acme ltd",
          status: "pending",
          created_at: now,
          updated_at: now
        }
      ])
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

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

  it "has one onboarding_session" do
    expect(applicant).to have_one(:onboarding_session)
      .with_foreign_key(:applicant_id)
      .dependent(:destroy)
  end

  it "has many applicant_users" do
    expect(applicant).to have_many(:applicant_users)
      .with_foreign_key(:applicant_id)
  end

  it "has many registry_profiles" do
    expect(applicant).to have_many(:registry_profiles)
      .class_name("Registry::Profile")
      .dependent(:destroy)
  end

  it "defaults status to pending" do
    expect(applicant.status).to eq("pending")
  end

  it "uses id as to_param" do
    saved = create(:applicant)
    expect(saved.to_param).to eq(saved.id)
  end

  describe "registry fields" do
    it "allows company_number and registry_jurisdiction to be blank" do
      applicant.company_number = nil
      applicant.registry_jurisdiction = nil
      expect(applicant).to be_valid
    end

    it "defines registry_jurisdiction as an enum limited to gb/mt/cy" do
      expect(described_class.registry_jurisdictions).to eq(
        "gb" => "gb", "mt" => "mt", "cy" => "cy"
      )
    end

    it "rejects a registry_jurisdiction outside the enum" do
      applicant.registry_jurisdiction = "us"

      expect(applicant).not_to be_valid
      expect(applicant.errors[:registry_jurisdiction]).not_to be_empty
    end

    it "persists a company_number and registry_jurisdiction" do
      saved = create(:applicant, company_number: "12345678", registry_jurisdiction: "gb")

      expect(saved.reload.company_number).to eq("12345678")
      expect(saved.reload.registry_jurisdiction).to eq("gb")
    end

    it "strips leading and trailing whitespace from company_number" do
      applicant.company_number = " 12345678 "
      applicant.valid?

      expect(applicant.company_number).to eq("12345678")
    end

    it "leaves a nil company_number as nil" do
      applicant.company_number = nil
      applicant.valid?

      expect(applicant.company_number).to be_nil
    end
  end
end
