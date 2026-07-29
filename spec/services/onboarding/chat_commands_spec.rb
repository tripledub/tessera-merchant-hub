# frozen_string_literal: true

require "rails_helper"

RSpec.describe Onboarding::ChatCommands do
  describe ".detect" do
    it "detects help" do
      expect(described_class.detect("help")).to eq(:help)
    end

    it "detects save and save and quit" do
      expect(described_class.detect("save")).to eq(:save)
      expect(described_class.detect("save and quit")).to eq(:save)
      expect(described_class.detect("save & quit")).to eq(:save)
    end

    it "detects skip and next" do
      expect(described_class.detect("skip")).to eq(:skip)
      expect(described_class.detect("next")).to eq(:skip)
    end

    it "is case-insensitive and ignores surrounding whitespace and punctuation" do
      expect(described_class.detect("  Help!  ")).to eq(:help)
      expect(described_class.detect("SKIP.")).to eq(:skip)
    end

    it "returns nil for ordinary conversational messages" do
      expect(described_class.detect("The company is Acme Ltd")).to be_nil
      expect(described_class.detect("I want to skip to the good part")).to be_nil
      expect(described_class.detect("")).to be_nil
      expect(described_class.detect(nil)).to be_nil
    end
  end
end
