# frozen_string_literal: true

require "rails_helper"

RSpec.describe Registry::PersonWithSignificantControl, type: :model do
  subject(:psc) { build(:registry_person_with_significant_control) }

  describe "associations" do
    it { is_expected.to belong_to(:registry_profile) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:kind) }
  end

  it "is valid with valid attributes" do
    expect(psc).to be_valid
  end

  it "allows ceased_on to be blank" do
    psc.ceased_on = nil
    expect(psc).to be_valid
  end

  it "defaults natures_of_control to an empty array" do
    expect(described_class.new.natures_of_control).to eq([])
  end

  it "persists natures_of_control as a string array" do
    psc.natures_of_control = [ "ownership-of-shares-75-to-100-percent", "voting-rights-75-to-100-percent" ]
    psc.save!

    expect(psc.reload.natures_of_control).to eq([ "ownership-of-shares-75-to-100-percent", "voting-rights-75-to-100-percent" ])
  end

  it "allows date_of_birth_month/year and address fields to be blank (corporate PSCs lack them)" do
    psc.date_of_birth_month = nil
    psc.date_of_birth_year = nil
    psc.nationality = nil
    psc.line1 = nil

    expect(psc).to be_valid
  end
end
