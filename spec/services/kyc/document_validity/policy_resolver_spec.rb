# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::DocumentValidity::PolicyResolver do
  describe ".resolve" do
    it "returns nil when no policy exists for the document type" do
      expect(described_class.resolve(document_type: "passport", reference_date: Date.current)).to be_nil
    end

    it "returns the policy effective on the exact effective_from date" do
      policy = Kyc::DocumentValidityPolicy.publish!(document_type: "passport", effective_from: Date.new(2026, 1, 1),
                                                      mode: :expires, required_dates: [ "expiry" ])

      resolved = described_class.resolve(document_type: "passport", reference_date: Date.new(2026, 1, 1))

      expect(resolved).to eq(policy)
    end

    it "returns nil when the reference date is before the policy's effective_from" do
      Kyc::DocumentValidityPolicy.publish!(document_type: "passport", effective_from: Date.new(2026, 1, 1),
                                            mode: :expires, required_dates: [ "expiry" ])

      resolved = described_class.resolve(document_type: "passport", reference_date: Date.new(2025, 12, 31))

      expect(resolved).to be_nil
    end

    it "returns the policy the day after effective_from" do
      policy = Kyc::DocumentValidityPolicy.publish!(document_type: "passport", effective_from: Date.new(2026, 1, 1),
                                                      mode: :expires, required_dates: [ "expiry" ])

      resolved = described_class.resolve(document_type: "passport", reference_date: Date.new(2026, 1, 2))

      expect(resolved).to eq(policy)
    end

    it "returns the highest-version policy effective for the reference date across multiple versions" do
      Kyc::DocumentValidityPolicy.publish!(document_type: "passport", effective_from: Date.new(2025, 1, 1),
                                            mode: :expires, required_dates: [ "expiry" ])
      v2 = Kyc::DocumentValidityPolicy.publish!(document_type: "passport", effective_from: Date.new(2026, 1, 1),
                                                 mode: :expires, required_dates: [ "expiry" ])

      resolved = described_class.resolve(document_type: "passport", reference_date: Date.new(2026, 6, 1))

      expect(resolved).to eq(v2)
    end

    it "falls back to an earlier version when the reference date predates the newest version" do
      v1 = Kyc::DocumentValidityPolicy.publish!(document_type: "passport", effective_from: Date.new(2025, 1, 1),
                                                 mode: :expires, required_dates: [ "expiry" ])
      Kyc::DocumentValidityPolicy.publish!(document_type: "passport", effective_from: Date.new(2026, 1, 1),
                                            mode: :expires, required_dates: [ "expiry" ])

      resolved = described_class.resolve(document_type: "passport", reference_date: Date.new(2025, 6, 1))

      expect(resolved).to eq(v1)
    end

    it "returns nil when the only applicable policy is disabled" do
      Kyc::DocumentValidityPolicy.publish!(document_type: "passport", effective_from: Date.new(2026, 1, 1),
                                            mode: :expires, required_dates: [ "expiry" ], enabled: false)

      resolved = described_class.resolve(document_type: "passport", reference_date: Date.new(2026, 6, 1))

      expect(resolved).to be_nil
    end

    it "skips a disabled newer version and returns an enabled earlier one" do
      v1 = Kyc::DocumentValidityPolicy.publish!(document_type: "passport", effective_from: Date.new(2025, 1, 1),
                                                 mode: :expires, required_dates: [ "expiry" ])
      Kyc::DocumentValidityPolicy.publish!(document_type: "passport", effective_from: Date.new(2026, 1, 1),
                                            mode: :expires, required_dates: [ "expiry" ], enabled: false)

      resolved = described_class.resolve(document_type: "passport", reference_date: Date.new(2026, 6, 1))

      expect(resolved).to eq(v1)
    end

    it "defaults reference_date to the current date" do
      policy = Kyc::DocumentValidityPolicy.publish!(document_type: "passport", effective_from: 1.day.ago.to_date,
                                                      mode: :expires, required_dates: [ "expiry" ])

      expect(described_class.resolve(document_type: "passport")).to eq(policy)
    end

    it "scopes resolution to the requested document type" do
      Kyc::DocumentValidityPolicy.publish!(document_type: "passport", effective_from: Date.current, mode: :expires,
                                            required_dates: [ "expiry" ])

      resolved = described_class.resolve(document_type: "utility_bill", reference_date: Date.current)

      expect(resolved).to be_nil
    end
  end
end
