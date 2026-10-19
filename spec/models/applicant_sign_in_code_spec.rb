# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicantSignInCode do
  describe ".generate_code" do
    it "makes six digits, zero-padded" do
      allow(SecureRandom).to receive(:random_number).with(1_000_000).and_return(42)

      expect(described_class.generate_code).to eq("000042")
    end

    it "only ever makes six digits" do
      expect(Array.new(200) { described_class.generate_code }).to all(match(/\A\d{6}\z/))
    end
  end

  describe "the stored digest" do
    let(:record) { create(:applicant_sign_in_code, code: "482913") }

    it "is not the code, and the row holds no plaintext code" do
      expect(record.code_digest).not_to eq("482913")
      expect(record.attributes.values.map(&:to_s)).not_to include("482913")
    end

    it "differs between records for the same code (salted with the record id)" do
      other = create(:applicant_sign_in_code, code: "482913")

      expect(other.code_digest).not_to eq(record.code_digest)
    end

    it "matches the right code and rejects others, whatever their type or spacing" do
      expect(record.matches?("482913")).to be(true)
      expect(record.matches?("482914")).to be(false)
      expect(record.matches?("")).to be(false)
      expect(record.matches?(nil)).to be(false)
      expect(record.matches?(482_913)).to be(true)
    end

    it "compares in constant time" do
      allow(ActiveSupport::SecurityUtils).to receive(:secure_compare).and_call_original

      record.matches?("482913")

      expect(ActiveSupport::SecurityUtils).to have_received(:secure_compare)
    end

    it "depends on the app secret, so a database leak alone cannot be brute-forced" do
      with_secret = described_class.digest_for(id: record.id, code: "482913")
      allow(Rails.application).to receive(:key_generator)
        .and_return(ActiveSupport::KeyGenerator.new("a different secret", iterations: 1))

      expect(described_class.digest_for(id: record.id, code: "482913")).not_to eq(with_secret)
    end
  end

  describe "state" do
    it "knows when it has expired, been used, or locked" do
      record = create(:applicant_sign_in_code)
      expect(record).not_to be_expired
      expect(record).not_to be_consumed
      expect(record).not_to be_locked

      expect(build(:applicant_sign_in_code, expires_at: 1.second.ago)).to be_expired
      expect(build(:applicant_sign_in_code, consumed_at: Time.current)).to be_consumed
      expect(build(:applicant_sign_in_code, attempts: described_class::MAX_ATTEMPTS)).to be_locked
      expect(build(:applicant_sign_in_code, invalidated_at: Time.current)).to be_locked
    end
  end

  it "is removed with its applicant" do
    record = create(:applicant_sign_in_code)

    expect { record.applicant.destroy! }.to change(described_class, :count).by(-1)
  end

  it "normalises the email" do
    expect(build(:applicant_sign_in_code, email: "  Applicant@Example.COM ").email).to eq("applicant@example.com")
  end

  it "needs an applicant, an email, a digest and an expiry" do
    record = described_class.new

    expect(record).not_to be_valid
    expect(record.errors.attribute_names).to include(:applicant, :email, :code_digest, :expires_at)
  end
end
