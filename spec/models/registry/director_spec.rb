# frozen_string_literal: true

require "rails_helper"

RSpec.describe Registry::Director, type: :model do
  subject(:director) { build(:registry_director) }

  describe "associations" do
    it { is_expected.to belong_to(:registry_profile) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:role) }
  end

  it "is valid with valid attributes" do
    expect(director).to be_valid
  end

  it "allows resigned_on to be blank" do
    director.resigned_on = nil
    expect(director).to be_valid
  end
end
