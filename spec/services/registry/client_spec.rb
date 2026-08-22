# frozen_string_literal: true

require "rails_helper"

RSpec.describe Registry::Client do
  describe "#fetch" do
    it "raises NotImplementedError, requiring subclasses to implement it" do
      expect { described_class.new.fetch(company_number: "12345678") }.to raise_error(NotImplementedError)
    end
  end
end
