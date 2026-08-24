# frozen_string_literal: true

require "rails_helper"

RSpec.describe Registry::Lookup do
  describe "CLIENTS" do
    it "registers Registry::CompaniesHouseUkClient for the gb jurisdiction" do
      expect(described_class::CLIENTS["gb"]).to eq(Registry::CompaniesHouseUkClient)
    end
  end
end
