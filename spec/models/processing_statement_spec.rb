# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProcessingStatement, type: :model do
  describe "#mappable?" do
    it "allows initial mapping and recovery mapping only" do
      expect(build(:processing_statement, status: :uploaded)).to be_mappable
      expect(build(:processing_statement, status: :error)).to be_mappable
      expect(build(:processing_statement, status: :mapped)).not_to be_mappable
      expect(build(:processing_statement, status: :processed)).not_to be_mappable
    end
  end

  describe "#removable?" do
    it "allows removal only after an import error" do
      expect(build(:processing_statement, status: :error)).to be_removable
      expect(build(:processing_statement, status: :uploaded)).not_to be_removable
      expect(build(:processing_statement, status: :mapped)).not_to be_removable
      expect(build(:processing_statement, status: :processed)).not_to be_removable
    end
  end
end
