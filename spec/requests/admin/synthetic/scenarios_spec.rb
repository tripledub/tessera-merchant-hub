# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Synthetic::Scenarios", type: :request do
  let_it_be(:psp_admin)   { create(:user, :psp_admin) }
  let_it_be(:psp_support) { create(:user, :psp_support) }

  before { Synthetic::PersonaSeed.call }

  describe "with synthetic data disabled" do
    include_context "with synthetic data disabled"

    before { sign_in psp_admin }

    it "404s the index, even for psp_admin" do
      get admin_synthetic_scenarios_path
      expect(response).to have_http_status(:not_found)
    end

    it "404s download" do
      get download_admin_synthetic_scenario_path("two-directors-one-passport")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "with synthetic data enabled" do
    include_context "with synthetic data enabled"

    it "lists scenarios with ground truth and Qase cases for psp_admin" do
      sign_in psp_admin

      get admin_synthetic_scenarios_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Two directors, one uploaded passport")
      expect(response.body).to include("KYN-29")
    end

    it "returns 403 for index when signed in as psp_support" do
      sign_in psp_support
      get admin_synthetic_scenarios_path
      expect(response).to have_http_status(:forbidden)
    end

    it "downloads a zip document pack for psp_admin" do
      sign_in psp_admin

      get download_admin_synthetic_scenario_path("two-directors-one-passport")

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/zip")
    end

    it "returns 403 for download when signed in as psp_support" do
      sign_in psp_support
      get download_admin_synthetic_scenario_path("two-directors-one-passport")
      expect(response).to have_http_status(:forbidden)
    end

    it "404s downloading an unknown scenario for psp_admin" do
      sign_in psp_admin
      get download_admin_synthetic_scenario_path("nonexistent")
      expect(response).to have_http_status(:not_found)
    end
  end
end
