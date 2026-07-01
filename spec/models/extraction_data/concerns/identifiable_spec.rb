# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExtractionData::Concerns::Identifiable do
  let(:dummy_class) do
    Class.new(ExtractionData::Base) { include ExtractionData::Concerns::Identifiable }
  end

  describe "#to_matcher_hash" do
    it "raises NotImplementedError if the including class doesn't override person_full_name" do
      expect { dummy_class.new.to_matcher_hash }.to raise_error(NotImplementedError)
    end
  end

  describe "ExtractionData::Passport" do
    it "maps full_name to person_full_name" do
      data = ExtractionData::Passport.new(full_name: "Jane Smith", date_of_birth: "1990-01-15")
      expect(data.person_full_name).to eq("Jane Smith")
      expect(data.person_date_of_birth).to eq(Date.parse("1990-01-15"))
    end

    it "builds a matcher hash" do
      data = ExtractionData::Passport.new(full_name: "Jane Smith", date_of_birth: "1990-01-15")
      expect(data.to_matcher_hash).to eq("full_name" => "Jane Smith", "date_of_birth" => Date.parse("1990-01-15"))
    end
  end

  describe "ExtractionData::DrivingLicence" do
    it "maps full_name and date_of_birth to the normalized interface" do
      data = ExtractionData::DrivingLicence.new(full_name: "John Doe", date_of_birth: "1985-03-20")
      expect(data.person_full_name).to eq("John Doe")
      expect(data.person_date_of_birth).to eq(Date.parse("1985-03-20"))
    end
  end
end
