# frozen_string_literal: true

require "rails_helper"

# MH-310: creating and previewing applicants against the Utopia (xu) synthetic
# registry, and the gate that keeps it out of production.
RSpec.describe "Applicants: synthetic Utopia registry", type: :request do
  let_it_be(:psp_admin) { create(:user, :psp_admin) }

  before { sign_in psp_admin }

  def jurisdiction_select(html)
    Nokogiri::HTML(html).at_css("select[name='applicant[registry_jurisdiction]']")
  end

  describe "GET /applicants/new" do
    context "when synthetic data is disabled" do
      include_context "with synthetic data disabled"

      it "offers no jurisdiction choice" do
        get new_applicant_path

        expect(response).to have_http_status(:ok)
        expect(jurisdiction_select(response.body)).to be_nil
      end
    end

    context "when synthetic data is enabled" do
      include_context "with synthetic data enabled"

      it "offers the United Kingdom and Utopia" do
        get new_applicant_path

        select = jurisdiction_select(response.body)
        expect(select.css("option").map { |o| o["value"] }).to eq(%w[gb xu])
        expect(select.at_css("option[value='xu']").text).to include("Utopia")
      end
    end
  end

  describe "POST /applicants" do
    let(:xu_params) { { name: "Utopia Test Co", company_number: "XU000002", registry_jurisdiction: "xu" } }

    context "when synthetic data is enabled" do
      include_context "with synthetic data enabled"

      it "creates the applicant on Utopia and fills its principals from the synthetic registry" do
        expect { post applicants_path, params: { applicant: xu_params } }.to change(Applicant, :count).by(1)

        created = Applicant.find_by!(name: "Utopia Test Co")
        expect(response).to redirect_to(applicant_path(created))
        expect(created.registry_jurisdiction).to eq("xu")
        expect(created.company_name).to eq("Utopia Specimen Holdings Ltd")
        expect(created.registry_profiles.count).to eq(1)
        expect(created.kyc_principals.pluck(:name, :role, :status, :source)).to contain_exactly(
          [ "TESTPERSON, Alex", "director", "confirmed", "registry_fetched" ],
          [ "EXAMPLESON, Morgan Lee", "director", "confirmed", "registry_fetched" ]
        )
      end

      it "never calls Companies House" do
        allow(Registry::CompaniesHouseUkClient).to receive(:new)

        post applicants_path, params: { applicant: xu_params }

        expect(Registry::CompaniesHouseUkClient).not_to have_received(:new)
      end

      it "treats an unknown company number as not found" do
        post applicants_path, params: { applicant: xu_params.merge(company_number: "XU999999") }

        created = Applicant.find_by!(name: "Utopia Test Co")
        expect(created.registry_profiles).to be_empty
        expect(flash[:alert]).to eq(I18n.t("flash.applicants.registry_lookup_failed"))
      end
    end

    context "when synthetic data is disabled" do
      include_context "with synthetic data disabled"

      it "rejects a tampered xu jurisdiction and creates nothing" do
        expect { post applicants_path, params: { applicant: xu_params } }.not_to change(Applicant, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "with a jurisdiction that cannot be selected" do
      include_context "with synthetic data enabled"

      it "falls back to gb" do
        post applicants_path, params: { applicant: { name: "Some Co", registry_jurisdiction: "mt" } }

        expect(Applicant.find_by!(name: "Some Co").registry_jurisdiction).to eq("gb")
      end
    end

    context "without a jurisdiction param" do
      include_context "with synthetic data disabled"

      it "defaults to gb, as before" do
        post applicants_path, params: { applicant: { name: "Plain Co" } }

        expect(Applicant.find_by!(name: "Plain Co").registry_jurisdiction).to eq("gb")
      end
    end
  end

  describe "POST /applicants/registry_preview" do
    let(:params) { { applicant: { company_number: "XU000002", registry_jurisdiction: "xu" } } }

    context "when synthetic data is enabled" do
      include_context "with synthetic data enabled"

      it "previews the synthetic company without touching Companies House or persisting anything" do
        allow(Registry::CompaniesHouseUkClient).to receive(:new)

        expect { post registry_preview_applicants_path, params: params, as: :turbo_stream }
          .not_to change(Applicant, :count)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Utopia Specimen Holdings Ltd")
        expect(Registry::CompaniesHouseUkClient).not_to have_received(:new)
      end
    end

    context "when synthetic data is disabled" do
      include_context "with synthetic data disabled"

      it "reports the jurisdiction as unsupported and never calls Companies House" do
        allow(Registry::CompaniesHouseUkClient).to receive(:new)

        post registry_preview_applicants_path, params: params, as: :turbo_stream

        expect(response.body).to include(ERB::Util.html_escape(I18n.t("applicants.registry_preview.errors.not_supported")))
        expect(Registry::CompaniesHouseUkClient).not_to have_received(:new)
      end
    end
  end
end
