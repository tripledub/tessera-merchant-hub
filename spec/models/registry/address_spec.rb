# frozen_string_literal: true

require "rails_helper"

RSpec.describe Registry::Address, type: :model do
  subject(:address) { build(:registry_address) }

  describe "associations" do
    it { is_expected.to belong_to(:registry_profile) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:line1) }
  end

  describe "kind enum" do
    it "defines kind as an enum limited to registered/trading" do
      expect(described_class.kinds).to eq("registered" => "registered", "trading" => "trading")
    end

    it "rejects a kind outside the enum" do
      address.kind = "postal"

      expect(address).not_to be_valid
      expect(address.errors[:kind]).not_to be_empty
    end
  end

  it "is valid with valid attributes" do
    expect(address).to be_valid
  end
end
