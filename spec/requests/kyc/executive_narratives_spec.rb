# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ExecutiveNarratives", type: :request do
  let_it_be(:psp_admin)   { create(:user, :psp_admin) }
  let_it_be(:psp_support) { create(:user, :psp_support) }
  let_it_be(:applicant)   { create(:applicant) }

  let(:mock_adapter) { instance_double(Kyc::Inference::Base) }
  let(:narrative_response) do
    {
      "executive_overview" => "Simple corporate structure with one UBO.",
      "risk_factors" => [ "No significant risks" ],
      "recommended_actions" => [ "Continue monitoring" ],
      "risk_assessment" => "low"
    }
  end

  before do
    allow(Kyc::Inference).to receive(:adapter).and_return(mock_adapter)
    allow(mock_adapter).to receive(:generate).and_return(narrative_response)
  end

  describe "GET /applicants/:applicant_id/kyc/executive_narrative" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "returns a PDF attachment" do
        get applicant_kyc_executive_narrative_path(applicant)

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("application/pdf")
        expect(response.headers["Content-Disposition"]).to include("attachment")
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns a PDF" do
        get applicant_kyc_executive_narrative_path(applicant)

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("application/pdf")
      end
    end
  end

  describe "POST /applicants/:applicant_id/kyc/executive_narrative" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "generates narrative and responds with turbo stream" do
        post applicant_kyc_executive_narrative_path(applicant),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("executive-narrative-content")
        expect(applicant.reload.executive_narrative).to eq(narrative_response)
      end

      it "rate limits regeneration within 60 seconds" do
        applicant.update!(
          executive_narrative: narrative_response,
          executive_narrative_generated_at: 30.seconds.ago
        )

        post applicant_kyc_executive_narrative_path(applicant),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Please wait")
        expect(mock_adapter).not_to have_received(:generate)
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "denies access to generate narrative" do
        post applicant_kyc_executive_narrative_path(applicant)

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
