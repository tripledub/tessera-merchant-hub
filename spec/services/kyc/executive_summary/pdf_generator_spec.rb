# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::ExecutiveSummary::PdfGenerator, type: :service do
  let(:applicant) { create(:applicant) }

  it "generates valid PDF data" do
    pdf_data = described_class.call(applicant)

    expect(pdf_data).to start_with("%PDF")
  end

  it "includes the applicant name" do
    pdf_data = described_class.call(applicant)
    text = PDF::Inspector::Text.analyze(pdf_data).strings.join(" ")

    expect(text).to include(applicant.name)
  end

  it "includes section headings" do
    pdf_data = described_class.call(applicant)
    text = PDF::Inspector::Text.analyze(pdf_data).strings.join(" ")

    expect(text).to include("Ownership Overview")
    expect(text).to include("Document Status")
  end

  context "with narrative data" do
    before do
      applicant.update!(
        executive_narrative: {
          "executive_overview" => "The applicant has a simple ownership structure.",
          "risk_factors" => [ "No significant risks identified" ],
          "recommended_actions" => [ "Continue monitoring" ],
          "risk_assessment" => "low"
        },
        executive_narrative_generated_at: Time.current
      )
    end

    it "includes narrative content in the PDF" do
      pdf_data = described_class.call(applicant)
      text = PDF::Inspector::Text.analyze(pdf_data).strings.join(" ")

      expect(text).to include("simple ownership structure")
    end
  end
end
