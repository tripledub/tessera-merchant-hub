# frozen_string_literal: true

require "rails_helper"

RSpec.describe Merchants::UpdateProfile do
  let(:merchant) { create(:merchant, contact_email: nil, country_code: nil) }

  describe ".call" do
    it "updates permitted profile fields" do
      result = described_class.call(merchant, {
        contact_email: "billing@acme.com",
        support_url: "https://acme.com/support",
        address_line1: "1 High Street",
        city: "London",
        country_code: "gb"
      })

      expect(result.errors).to be_empty
      expect(merchant.reload.contact_email).to eq("billing@acme.com")
      expect(merchant.reload.city).to eq("London")
      expect(merchant.reload.country_code).to eq("GB")
    end

    it "returns the merchant with errors when invalid" do
      result = described_class.call(merchant, { contact_email: "not-an-email" })
      expect(result.errors[:contact_email]).to be_present
    end

    it "does not update unpermitted fields (e.g. merchant_id)" do
      original_id = merchant.merchant_id
      described_class.call(merchant, { merchant_id: "hacked_id" })
      expect(merchant.reload.merchant_id).to eq(original_id)
    end
  end
end
