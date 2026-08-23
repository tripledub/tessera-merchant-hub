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

  it "defines the supported sectors with a general default" do
    expect(described_class.sectors).to eq(
      "general" => "general",
      "crypto_exchange" => "crypto_exchange",
      "gambling" => "gambling",
      "forex_brokerage" => "forex_brokerage",
      "proprietary_trading" => "proprietary_trading"
    )
    expect(described_class.new.sector).to eq("general")
  end

  describe "sector changes" do
    it "allows a sector change before document collection begins" do
      saved = create(:applicant, sector: :general)
      create(:onboarding_session, applicant: saved, current_stage: :jurisdictions)

      expect { saved.update!(sector: :crypto_exchange) }
        .to change { saved.reload.sector }
        .from("general").to("crypto_exchange")
    end

    it "rejects changing from general once document collection begins" do
      saved = create(:applicant, sector: :general)
      create(:onboarding_session, applicant: saved, current_stage: :document_collection)

      saved.sector = :crypto_exchange

      expect(saved).not_to be_valid
      expect(saved.errors.details.fetch(:sector)).to include(error: :locked_after_document_collection)
      expect(saved.save).to be(false)
      expect(saved.reload.sector).to eq("general")
    end

    it "rejects changing from a policy sector when a retained checklist proves collection already began" do
      saved = create(:applicant, sector: :crypto_exchange)
      create(
        :onboarding_session,
        applicant: saved,
        current_stage: :jurisdictions,
        document_checklist: [ { "category" => "sector_policy" } ]
      )

      saved.sector = :general

      expect(saved).not_to be_valid
      expect(saved.errors.details.fetch(:sector)).to include(error: :locked_after_document_collection)
      expect(saved.save).to be(false)
      expect(saved.reload.sector).to eq("crypto_exchange")
    end

    it "rejects a sector change when a KYC document exists without an onboarding session" do
      saved = create(:applicant, sector: :crypto_exchange)
      create(:kyc_document, applicant: saved)

      expect(saved.onboarding_session).to be_nil
      expect(saved.sector_locked?).to be true

      saved.sector = :general

      expect(saved).not_to be_valid
      expect(saved.errors.details.fetch(:sector)).to include(error: :locked_after_document_collection)
      expect(saved.save).to be(false)
      expect(saved.reload.sector).to eq("crypto_exchange")
    end
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
  end
end
