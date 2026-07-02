# frozen_string_literal: true

require "rails_helper"

RSpec.describe Address, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:addressable) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:line1) }
    it { is_expected.to validate_presence_of(:city) }
    it { is_expected.to validate_presence_of(:country) }
  end

  describe Address::Business do
    it "is an Address" do
      expect(described_class.superclass).to eq(Address)
    end
  end

  describe "primary uniqueness" do
    let(:applicant) { create(:applicant) }

    it "allows only one primary address per addressable+type" do
      create(:address, :business, :primary, addressable: applicant)
      duplicate = build(:address, :business, :primary, addressable: applicant)
      expect(duplicate).not_to be_valid
    end

    it "allows multiple non-primary addresses per addressable+type" do
      create(:address, :business, addressable: applicant)
      second = build(:address, :business, addressable: applicant)
      expect(second).to be_valid
    end

    it "allows primary addresses of different types on the same addressable" do
      create(:address, :business, :primary, addressable: applicant)
      individual = build(:address, :individual, :primary, addressable: applicant)
      expect(individual).to be_valid
    end
  end
end
