# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::Synthetic::PassportPdf do
  let(:persona) do
    create(:synthetic_persona, given_names: "Alex", surname: "Testperson",
      date_of_birth: Date.new(1990, 5, 20), sex: :female)
  end

  let(:options) { { place_of_birth: "Testville", passport_number: "L898902C3", expiry_preset: "valid" } }

  def text_for(pdf_data)
    PDF::Inspector::Text.analyze(pdf_data).strings.join(" ")
  end

  it "generates valid PDF data" do
    expect(described_class.call(persona: persona, options: options)).to start_with("%PDF")
  end

  it "shows the guardrails: SPECIMEN watermark, TEST DATA marking and Utopia as the issuing state" do
    text = text_for(described_class.call(persona: persona, options: options))

    expect(text).to include("SPECIMEN")
    expect(text).to include("TEST DATA")
    expect(text).to include("REPUBLIC OF UTOPIA")
  end

  it "includes the persona's entered fields" do
    text = text_for(described_class.call(persona: persona, options: options))

    expect(text).to include("Testperson")
    expect(text).to include("Alex")
    expect(text).to include("Testville")
    expect(text).to include("L898902C3")
  end

  it "includes a valid MRZ" do
    text = text_for(described_class.call(persona: persona, options: options))
    expected_mrz = Kyc::Synthetic::PassportMrz.call(
      persona: persona, document_number: "L898902C3", expiry_date: described_class.expiry_date_for("valid")
    )

    expect(text).to include(expected_mrz.line1)
    expect(text).to include(expected_mrz.line2)
  end

  it "produces the same content for the same persona and options (deterministic)" do
    first = text_for(described_class.call(persona: persona, options: options))
    second = text_for(described_class.call(persona: persona, options: options))

    expect(first).to eq(second)
  end

  describe ".expiry_date_for" do
    it "resolves 'valid' to two years out" do
      expect(described_class.expiry_date_for("valid")).to eq(Date.current + 2.years)
    end

    it "resolves 'expires_60' to 60 days out" do
      expect(described_class.expiry_date_for("expires_60")).to eq(Date.current + 60.days)
    end

    it "resolves 'expires_30' to 30 days out" do
      expect(described_class.expiry_date_for("expires_30")).to eq(Date.current + 30.days)
    end

    it "resolves 'expired' to yesterday" do
      expect(described_class.expiry_date_for("expired")).to eq(Date.current - 1.day)
    end

    it "defaults an unknown preset to 'valid'" do
      expect(described_class.expiry_date_for("bogus")).to eq(Date.current + 2.years)
    end
  end
end
