# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::Inference::ResponseNormalizer do
  describe ".extract_json" do
    it "returns plain JSON unchanged" do
      expect(described_class.extract_json('{"a": 1}')).to eq('{"a": 1}')
    end

    it "strips a json code fence" do
      expect(described_class.extract_json("```json\n{\"a\": 1}\n```")).to eq('{"a": 1}')
    end

    it "strips an unlabelled code fence" do
      expect(described_class.extract_json("```\n{\"a\": 1}\n```")).to eq('{"a": 1}')
    end

    it "strips a fence with leading commentary before it" do
      text = "Sure, here is the JSON:\n```json\n{\"a\": 1}\n```"
      expect(described_class.extract_json(text)).to eq('{"a": 1}')
    end

    it "strips a fence with trailing commentary after it" do
      text = "```json\n{\"a\": 1}\n```\nLet me know if you need anything else!"
      expect(described_class.extract_json(text)).to eq('{"a": 1}')
    end

    it "recovers a truncated fence with no closing backticks" do
      text = "```json\n{\"a\": 1, \"b\": 2}"
      expect(described_class.extract_json(text)).to eq('{"a": 1, "b": 2}')
    end

    it "returns the original text when there is no JSON object to recover" do
      expect(described_class.extract_json("not json at all")).to eq("not json at all")
    end
  end
end
