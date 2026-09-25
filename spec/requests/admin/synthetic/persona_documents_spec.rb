# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Synthetic::PersonaDocuments", type: :request do
  let_it_be(:psp_admin)   { create(:user, :psp_admin) }
  let_it_be(:psp_support) { create(:user, :psp_support) }
  let_it_be(:persona)     { create(:synthetic_persona) }

  let(:valid_params) do
    { document_type: "passport", options: { place_of_birth: "Testville", passport_number: "L898902C3", expiry_preset: "valid" } }
  end

  describe "with synthetic data disabled" do
    include_context "with synthetic data disabled"

    before { sign_in psp_admin }

    it "404s" do
      post admin_synthetic_persona_documents_path(persona), params: valid_params
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "with synthetic data enabled" do
    include_context "with synthetic data enabled"

    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "streams a generated passport PDF" do
        post admin_synthetic_persona_documents_path(persona), params: valid_params

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("application/pdf")
        expect(response.body).to start_with("%PDF")
      end

      it "records the generation (acting user, type and options)" do
        expect {
          post admin_synthetic_persona_documents_path(persona), params: valid_params
        }.to change(Synthetic::GeneratedDocument, :count).by(1)

        record = Synthetic::GeneratedDocument.last
        expect(record.synthetic_persona).to eq(persona)
        expect(record.generated_by).to eq(psp_admin)
        expect(record.document_type).to eq("passport")
        expect(record.options["place_of_birth"]).to eq("Testville")
      end

      it "rejects an unknown document type" do
        post admin_synthetic_persona_documents_path(persona), params: valid_params.merge(document_type: "nonsense")

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "rejects a request missing required options" do
        post admin_synthetic_persona_documents_path(persona), params: { document_type: "passport", options: {} }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        post admin_synthetic_persona_documents_path(persona), params: valid_params
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
