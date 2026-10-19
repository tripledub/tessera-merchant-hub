# frozen_string_literal: true

require "rails_helper"

# MH-404: values that must reach a background job (a one-time code, a link)
# without being stored in plaintext in the queue database. Encrypted with a key
# derived from the app secret, bound to a purpose, and expiring.
RSpec.describe ShortLivedSecret do
  let(:purpose) { :applicant_sign_in_code }

  it "round-trips a value" do
    token = described_class.encrypt("482913", purpose: purpose, expires_in: 15.minutes)

    expect(described_class.decrypt(token, purpose: purpose)).to eq("482913")
  end

  it "does not contain the plaintext" do
    token = described_class.encrypt("482913", purpose: purpose, expires_in: 15.minutes)

    expect(token).not_to include("482913")
    expect(Base64.decode64(token.to_s.split("--").first.to_s)).not_to include("482913")
  end

  it "produces a different token each time for the same value" do
    first = described_class.encrypt("482913", purpose: purpose, expires_in: 15.minutes)
    second = described_class.encrypt("482913", purpose: purpose, expires_in: 15.minutes)

    expect(first).not_to eq(second)
  end

  it "returns nil once it has expired" do
    token = described_class.encrypt("482913", purpose: purpose, expires_in: 15.minutes)

    travel_to(16.minutes.from_now) do
      expect(described_class.decrypt(token, purpose: purpose)).to be_nil
    end
  end

  it "is only valid for the purpose it was made for" do
    token = described_class.encrypt("482913", purpose: purpose, expires_in: 15.minutes)

    expect(described_class.decrypt(token, purpose: :applicant_invitation_link)).to be_nil
  end

  it "returns nil for tampered, garbage or missing tokens" do
    token = described_class.encrypt("482913", purpose: purpose, expires_in: 15.minutes)

    expect(described_class.decrypt("#{token}x", purpose: purpose)).to be_nil
    expect(described_class.decrypt("not a token", purpose: purpose)).to be_nil
    expect(described_class.decrypt("", purpose: purpose)).to be_nil
    expect(described_class.decrypt(nil, purpose: purpose)).to be_nil
  end
end
