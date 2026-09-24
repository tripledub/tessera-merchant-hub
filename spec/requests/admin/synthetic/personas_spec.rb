# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Synthetic::Personas", type: :request do
  let_it_be(:psp_admin)   { create(:user, :psp_admin) }
  let_it_be(:psp_support) { create(:user, :psp_support) }

  describe "with synthetic data disabled (the default)" do
    include_context "with synthetic data disabled"

    before { sign_in psp_admin }

    it "404s the index, even for psp_admin" do
      get admin_synthetic_personas_path
      expect(response).to have_http_status(:not_found)
    end

    it "404s the new page" do
      get new_admin_synthetic_persona_path
      expect(response).to have_http_status(:not_found)
    end

    it "404s create" do
      post admin_synthetic_personas_path, params: { synthetic_persona: { given_names: "A", surname: "B", date_of_birth: "1990-01-01" } }
      expect(response).to have_http_status(:not_found)
    end

    it "404s show" do
      persona = create(:synthetic_persona)
      get admin_synthetic_persona_path(persona)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "with synthetic data enabled" do
    include_context "with synthetic data enabled"

    it "lists personas for psp_admin" do
      sign_in psp_admin
      persona = create(:synthetic_persona, given_names: "Jordan", surname: "Example")

      get admin_synthetic_personas_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(persona.full_name)
    end

    it "returns 403 for index when signed in as psp_support" do
      sign_in psp_support
      get admin_synthetic_personas_path
      expect(response).to have_http_status(:forbidden)
    end

    it "creates a persona and redirects to it for psp_admin" do
      sign_in psp_admin

      post admin_synthetic_personas_path, params: {
        synthetic_persona: { given_names: "Alex", surname: "Testperson", date_of_birth: "1990-01-01", sex: "female", jurisdiction: "xu" }
      }

      persona = Synthetic::Persona.find_by(given_names: "Alex", surname: "Testperson")
      expect(persona).to be_present
      expect(response).to redirect_to(admin_synthetic_persona_path(persona))
    end

    it "re-renders new with 422 on a missing required field for psp_admin" do
      sign_in psp_admin

      post admin_synthetic_personas_path, params: {
        synthetic_persona: { given_names: "", surname: "Testperson", date_of_birth: "1990-01-01" }
      }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 403 for create when signed in as psp_support" do
      sign_in psp_support

      post admin_synthetic_personas_path, params: {
        synthetic_persona: { given_names: "A", surname: "B", date_of_birth: "1990-01-01" }
      }
      expect(response).to have_http_status(:forbidden)
    end

    it "shows the persona for psp_admin" do
      sign_in psp_admin
      persona = create(:synthetic_persona)

      get admin_synthetic_persona_path(persona)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(persona.full_name)
    end

    it "returns 403 for show when signed in as psp_support" do
      sign_in psp_support
      persona = create(:synthetic_persona)
      get admin_synthetic_persona_path(persona)
      expect(response).to have_http_status(:forbidden)
    end

    it "writes a YAML file for the persona on export, for psp_admin" do
      sign_in psp_admin
      persona = create(:synthetic_persona)
      path = Synthetic::PersonaExport::DIR.join("#{persona.slug}.yml")

      begin
        post export_admin_synthetic_persona_path(persona)

        expect(response).to redirect_to(admin_synthetic_persona_path(persona))
        expect(File).to exist(path)
      ensure
        FileUtils.rm_f(path)
      end
    end
  end
end
