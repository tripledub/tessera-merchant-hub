# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::DocumentValidityPolicy, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:document_type) }
    it { is_expected.to validate_presence_of(:version) }
    it { is_expected.to validate_presence_of(:effective_from) }
    it { is_expected.to validate_presence_of(:mode) }

    it "validates uniqueness of version scoped to document_type" do
      described_class.publish!(document_type: "passport", effective_from: Date.current, mode: :expires,
                                required_dates: [ "expiry" ])

      duplicate = described_class.new(document_type: "passport", version: 1, effective_from: Date.current,
                                       mode: :expires, required_dates: [ "expiry" ])
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "requires max_age_months when mode is freshness" do
      policy = described_class.new(document_type: "utility_bill", version: 1, effective_from: Date.current,
                                    mode: :freshness, required_dates: [ "issued" ])
      expect(policy).not_to be_valid
      expect(policy.errors[:max_age_months]).to be_present
    end

    it "does not require max_age_months when mode is expires" do
      policy = described_class.new(document_type: "passport", version: 1, effective_from: Date.current,
                                    mode: :expires, required_dates: [ "expiry" ])
      expect(policy).to be_valid
    end
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:mode).with_values(expires: 0, freshness: 1) }
  end

  describe ".publish!" do
    it "creates version 1 for a new document type" do
      policy = described_class.publish!(document_type: "passport", effective_from: Date.current, mode: :expires,
                                         required_dates: [ "expiry" ], warning_thresholds: [ 90, 30 ])

      expect(policy.version).to eq(1)
      expect(policy.document_type).to eq("passport")
      expect(policy.warning_thresholds).to eq([ 90, 30 ])
      expect(policy).to be_enabled
      expect(policy).to be_blocking
    end

    it "increments the version for subsequent publishes of the same document type" do
      described_class.publish!(document_type: "passport", effective_from: 1.year.ago.to_date, mode: :expires,
                                required_dates: [ "expiry" ])
      second = described_class.publish!(document_type: "passport", effective_from: Date.current, mode: :expires,
                                         required_dates: [ "expiry" ], warning_thresholds: [ 60 ])

      expect(second.version).to eq(2)
    end

    it "tracks versions independently per document type" do
      described_class.publish!(document_type: "passport", effective_from: Date.current, mode: :expires,
                                required_dates: [ "expiry" ])
      utility_policy = described_class.publish!(document_type: "utility_bill", effective_from: Date.current,
                                                  mode: :freshness, required_dates: [ "issued" ],
                                                  max_age_months: 3)

      expect(utility_policy.version).to eq(1)
    end
  end

  describe "immutability" do
    let(:policy) do
      described_class.publish!(document_type: "passport", effective_from: Date.current, mode: :expires,
                                required_dates: [ "expiry" ], warning_thresholds: [ 90, 30 ])
    end

    it "allows toggling enabled" do
      expect { policy.update!(enabled: false) }.not_to raise_error
      expect(policy.reload.enabled).to be(false)
    end

    it "raises when attempting to change document_type" do
      expect { policy.update!(document_type: "utility_bill") }.to raise_error(Kyc::DocumentValidityPolicy::ImmutableError)
    end

    it "raises when attempting to change version" do
      expect { policy.update!(version: 99) }.to raise_error(Kyc::DocumentValidityPolicy::ImmutableError)
    end

    it "raises when attempting to change effective_from" do
      expect { policy.update!(effective_from: 1.day.from_now.to_date) }.to raise_error(Kyc::DocumentValidityPolicy::ImmutableError)
    end

    it "raises when attempting to change mode" do
      expect { policy.update!(mode: :freshness, max_age_months: 3) }.to raise_error(Kyc::DocumentValidityPolicy::ImmutableError)
    end

    it "raises when attempting to change required_dates" do
      expect { policy.update!(required_dates: [ "issued" ]) }.to raise_error(Kyc::DocumentValidityPolicy::ImmutableError)
    end

    it "raises when attempting to change warning_thresholds" do
      expect { policy.update!(warning_thresholds: [ 45 ]) }.to raise_error(Kyc::DocumentValidityPolicy::ImmutableError)
    end

    it "raises when attempting to change max_age_months" do
      utility_policy = described_class.publish!(document_type: "utility_bill", effective_from: Date.current,
                                                  mode: :freshness, required_dates: [ "issued" ],
                                                  max_age_months: 3)
      expect { utility_policy.update!(max_age_months: 6) }.to raise_error(Kyc::DocumentValidityPolicy::ImmutableError)
    end

    it "raises when attempting to change blocking" do
      expect { policy.update!(blocking: false) }.to raise_error(Kyc::DocumentValidityPolicy::ImmutableError)
    end
  end
end
