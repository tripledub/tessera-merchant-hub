# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::ExecutiveSummary::NarrativeGenerator, type: :service do
  let(:applicant) { create(:applicant) }
  let(:mock_adapter) { instance_double(Kyc::Inference::Base) }
  let(:narrative_response) do
    {
      "executive_overview" => "The applicant operates through a two-tier corporate structure with one individual UBO.",
      "risk_factors" => [ "Nominee structure detected", "Ownership percentages do not sum to 100%" ],
      "recommended_actions" => [ "Obtain declaration of trust for nominee entity" ],
      "risk_assessment" => "medium"
    }
  end

  before do
    allow(Kyc::Inference).to receive(:adapter).and_return(mock_adapter)
    allow(mock_adapter).to receive(:generate).and_return(narrative_response)
  end

  describe ".call" do
    it "generates and caches the narrative on the applicant" do
      result = described_class.call(applicant)

      expect(result).to eq(narrative_response)
      applicant.reload
      expect(applicant.executive_narrative).to eq(narrative_response)
      expect(applicant.executive_narrative_generated_at).to be_present
    end

    it "returns cached narrative without calling the adapter" do
      applicant.update!(executive_narrative: narrative_response, executive_narrative_generated_at: 1.hour.ago)

      result = described_class.call(applicant)

      expect(result).to eq(narrative_response)
      expect(mock_adapter).not_to have_received(:generate)
    end

    it "regenerates when force: true" do
      applicant.update!(executive_narrative: { "stale" => true }, executive_narrative_generated_at: 1.day.ago)

      result = described_class.call(applicant, force: true)

      expect(result).to eq(narrative_response)
      expect(mock_adapter).to have_received(:generate)
    end

    it "sends assembled data in the prompt" do
      described_class.call(applicant)

      expect(mock_adapter).to have_received(:generate).with(
        prompt: include("Due diligence data:")
      )
    end

    it "requests the correct JSON structure" do
      described_class.call(applicant)

      expect(mock_adapter).to have_received(:generate).with(
        prompt: include("executive_overview", "risk_factors", "recommended_actions", "risk_assessment")
      )
    end

    context "when inference raises an error" do
      before do
        allow(mock_adapter).to receive(:generate).and_raise(Kyc::Inference::Error, "rate limited")
      end

      it "wraps in NarrativeGenerator::Error" do
        expect { described_class.call(applicant) }
          .to raise_error(described_class::Error, /rate limited/)
      end
    end

    context "when inference returns non-Hash" do
      before do
        allow(mock_adapter).to receive(:generate).and_return("not json")
      end

      it "raises NarrativeGenerator::Error" do
        expect { described_class.call(applicant) }
          .to raise_error(described_class::Error, /Expected Hash/)
      end
    end
  end
end
