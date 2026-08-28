# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Applicants", type: :request do
  let_it_be(:psp_admin)      { create(:user, :psp_admin) }
  let_it_be(:psp_support)    { create(:user, :psp_support) }
  let_it_be(:merchant_admin) { create(:user, :merchant_admin) }

  let_it_be(:applicant_a) { create(:applicant, name: "Acme Corp") }
  let_it_be(:applicant_b) { create(:applicant, name: "Beta Ltd") }

  describe "GET /applicants" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "returns 200 and lists applicants" do
        get applicants_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Acme Corp")
        expect(response.body).to include("Beta Ltd")
      end

      it "does not render the Actions column when applicant deletion is disabled" do
        get applicants_path
        expect(response.body).not_to include(I18n.t("applicants.index.table.actions"))
        expect(response.body).not_to include("Delete applicant")
      end

      it "filters by name" do
        get applicants_path, params: { q: "Acme" }
        expect(response.body).to include("Acme Corp")
        expect(response.body).not_to include("Beta Ltd")
      end

      it "renders pagination when there is more than one page" do
        create_list(:applicant, 20)

        get applicants_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("page=2")
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 200" do
        get applicants_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 403" do
        get applicants_path
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when unauthenticated" do
      it "redirects to sign in" do
        get applicants_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "GET /applicants — Actions column" do
    around do |example|
      original = Rails.application.config.x.applicant_delete_enabled
      Rails.application.config.x.applicant_delete_enabled = true
      example.run
      Rails.application.config.x.applicant_delete_enabled = original
    end

    context "when signed in as psp_admin (can delete)" do
      before { sign_in psp_admin }

      it "shows the Actions column with matching header/row cell counts" do
        get applicants_path
        doc = Nokogiri::HTML(response.body)
        header_cells = doc.css("table thead th").count
        first_row_cells = doc.css("table tbody tr").first.css("td").count

        expect(response.body).to include(I18n.t("applicants.index.table.actions"))
        expect(header_cells).to eq(first_row_cells)
      end
    end

    context "when signed in as psp_support (cannot delete)" do
      before { sign_in psp_support }

      it "hides the Actions column with matching header/row cell counts" do
        get applicants_path
        doc = Nokogiri::HTML(response.body)
        header_cells = doc.css("table thead th").count
        first_row_cells = doc.css("table tbody tr").first.css("td").count

        expect(response.body).not_to include(I18n.t("applicants.index.table.actions"))
        expect(header_cells).to eq(first_row_cells)
      end
    end
  end

  describe "GET /applicants/:id" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "returns 200" do
        get applicant_path(applicant_a)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Acme Corp")
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 200" do
        get applicant_path(applicant_a)
        expect(response).to have_http_status(:ok)
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 403" do
        get applicant_path(applicant_a)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /applicants/new" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "returns 200 with a sector field" do
        get new_applicant_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('id="applicant_sector"')
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        get new_applicant_path
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /applicants" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "creates an applicant with the selected sector and redirects to show" do
        post applicants_path, params: {
          applicant: {
            name: "New Corp", company_name: "New Corp Ltd", contact_email: "info@new.com",
            sector: "crypto_exchange"
          }
        }
        created = Applicant.find_by!(name: "New Corp")
        expect(response).to redirect_to(applicant_path(created))
        expect(created.sector).to eq("crypto_exchange")
      end

      it "creates the applicant with a blank company_number, and redirects to show with a retry alert" do
        post applicants_path, params: { applicant: { name: "New Corp" } }

        created = Applicant.find_by!(name: "New Corp")
        expect(response).to redirect_to(applicant_path(created))
        expect(flash[:alert]).to be_present
        expect(created.registry_profiles).to be_empty
      end

      it "re-renders new with 422 on invalid params" do
        post applicants_path, params: { applicant: { name: "" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "when signed in as psp_admin, and the registry lookup succeeds" do
      let(:fake_client) { instance_double(Registry::CompaniesHouseUkClient) }
      let(:fetch_result) do
        Registry::FetchResult.success(
          company_name: "New Corp Ltd", status: "active", incorporated_on: Date.new(2020, 1, 1),
          directors: [ { name: "DOE, Jane", role: "director", appointed_on: Date.new(2020, 1, 1), resigned_on: nil } ],
          addresses: [],
          people_with_significant_control: [
            {
              name: "Mr John Smith", kind: "individual-person-with-significant-control",
              natures_of_control: [ "ownership-of-shares-75-to-100-percent" ],
              notified_on: Date.new(2020, 1, 1), ceased_on: nil, nationality: "British",
              date_of_birth_month: 1, date_of_birth_year: 1980,
              line1: nil, city: nil, postcode: nil, country: nil, registration_number: nil
            }
          ]
        )
      end

      before do
        sign_in psp_admin
        allow(Registry::CompaniesHouseUkClient).to receive(:new).and_return(fake_client)
        allow(fake_client).to receive(:fetch).with(company_number: "12345678").and_return(fetch_result)
      end

      it "creates the applicant, persists the registry snapshot, and redirects to show with a success notice" do
        post applicants_path, params: { applicant: { name: "New Corp", company_number: "12345678" } }

        created = Applicant.find_by!(name: "New Corp")
        expect(response).to redirect_to(applicant_path(created))
        expect(flash[:notice]).to be_present
        expect(created.registry_jurisdiction).to eq("gb")
        expect(created.company_name).to eq("New Corp Ltd")
        expect(created.registry_profiles.count).to eq(1)
      end

      it "promotes active directors, but not PSCs, to kyc_principals" do
        post applicants_path, params: { applicant: { name: "New Corp", company_number: "12345678" } }

        created = Applicant.find_by!(name: "New Corp")
        expect(created.kyc_principals.pluck(:name)).to contain_exactly("DOE, Jane")
      end

      it "flags the PSC as a UBO without creating any corporate entities" do
        post applicants_path, params: { applicant: { name: "New Corp", company_number: "12345678" } }

        created = Applicant.find_by!(name: "New Corp")
        expect(created.corporate_entities).to be_empty
        expect(Kyc::ValidationWarning.where(applicant: created, warning_type: :ubo_threshold_exceeded).count).to eq(1)
      end
    end

    context "when signed in as psp_admin, and the registry lookup fails" do
      let(:fake_client) { instance_double(Registry::CompaniesHouseUkClient) }
      let(:fetch_result) { Registry::FetchResult.failure(error_type: :not_found) }

      before do
        sign_in psp_admin
        allow(Registry::CompaniesHouseUkClient).to receive(:new).and_return(fake_client)
        allow(fake_client).to receive(:fetch).with(company_number: "00000000").and_return(fetch_result)
      end

      it "still creates the applicant, and redirects to show with a retry alert" do
        post applicants_path, params: { applicant: { name: "New Corp", company_number: "00000000" } }

        created = Applicant.find_by!(name: "New Corp")
        expect(response).to redirect_to(applicant_path(created))
        expect(flash[:alert]).to be_present
        expect(created.registry_profiles).to be_empty
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        post applicants_path, params: { applicant: { name: "X" } }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /applicants/registry_preview" do
    context "when signed in as psp_admin, and the company number is blank" do
      before { sign_in psp_admin }

      it "renders an inline validation message via turbo_stream" do
        post registry_preview_applicants_path, params: { applicant: { company_number: "" } },
          as: :turbo_stream

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      end
    end

    context "when signed in as psp_admin, and the lookup succeeds" do
      let(:fake_client) { instance_double(Registry::CompaniesHouseUkClient) }
      let(:fetch_result) do
        Registry::FetchResult.success(
          company_name: "Preview Corp Ltd", status: "active", incorporated_on: Date.new(2020, 1, 1),
          directors: [], addresses: []
        )
      end

      before do
        sign_in psp_admin
        allow(Registry::CompaniesHouseUkClient).to receive(:new).and_return(fake_client)
        allow(fake_client).to receive(:fetch).with(company_number: "12345678").and_return(fetch_result)
      end

      it "renders the company preview via turbo_stream without persisting anything" do
        expect {
          post registry_preview_applicants_path, params: { applicant: { company_number: "12345678" } },
            as: :turbo_stream
        }.not_to change(Applicant, :count)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Preview Corp Ltd")
      end
    end

    context "when signed in as psp_admin, and the lookup fails" do
      let(:fake_client) { instance_double(Registry::CompaniesHouseUkClient) }
      let(:fetch_result) { Registry::FetchResult.failure(error_type: :not_found) }

      before do
        sign_in psp_admin
        allow(Registry::CompaniesHouseUkClient).to receive(:new).and_return(fake_client)
        allow(fake_client).to receive(:fetch).with(company_number: "00000000").and_return(fetch_result)
      end

      it "renders an error message via turbo_stream without persisting anything" do
        expect {
          post registry_preview_applicants_path, params: { applicant: { company_number: "00000000" } },
            as: :turbo_stream
        }.not_to change(Applicant, :count)

        expect(response).to have_http_status(:ok)
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        post registry_preview_applicants_path, params: { applicant: { company_number: "12345678" } },
          as: :turbo_stream
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /applicants/:id/registry_lookup" do
    let(:applicant) { create(:applicant, company_number: "12345678", registry_jurisdiction: "gb") }

    context "when signed in as psp_admin, and the lookup succeeds" do
      let(:fake_client) { instance_double(Registry::CompaniesHouseUkClient) }
      let(:fetch_result) do
        Registry::FetchResult.success(
          company_name: "Acme Ltd", status: "active", incorporated_on: Date.new(2020, 1, 1),
          directors: [ { name: "DOE, Jane", role: "director", appointed_on: Date.new(2020, 1, 1), resigned_on: nil } ],
          addresses: [],
          people_with_significant_control: [
            {
              name: "Mr John Smith", kind: "individual-person-with-significant-control",
              natures_of_control: [ "ownership-of-shares-75-to-100-percent" ],
              notified_on: Date.new(2020, 1, 1), ceased_on: nil, nationality: "British",
              date_of_birth_month: 1, date_of_birth_year: 1980,
              line1: nil, city: nil, postcode: nil, country: nil, registration_number: nil
            }
          ]
        )
      end

      before do
        sign_in psp_admin
        allow(Registry::CompaniesHouseUkClient).to receive(:new).and_return(fake_client)
        allow(fake_client).to receive(:fetch).with(company_number: "12345678").and_return(fetch_result)
      end

      it "persists the registry snapshot and redirects to show with a success notice" do
        expect { post registry_lookup_applicant_path(applicant) }
          .to change { applicant.registry_profiles.count }.by(1)

        expect(response).to redirect_to(applicant_path(applicant))
        expect(flash[:notice]).to be_present
      end

      it "promotes active directors, but not PSCs, to kyc_principals" do
        expect { post registry_lookup_applicant_path(applicant) }
          .to change { applicant.kyc_principals.count }.by(1)

        expect(applicant.kyc_principals.pluck(:name)).to contain_exactly("DOE, Jane")
      end

      it "flags the PSC as a UBO without creating any corporate entities" do
        post registry_lookup_applicant_path(applicant)

        expect(applicant.corporate_entities).to be_empty
        expect(Kyc::ValidationWarning.where(applicant: applicant, warning_type: :ubo_threshold_exceeded).count).to eq(1)
      end

      it "renders the PSC on the Ownership tab" do
        post registry_lookup_applicant_path(applicant)

        get tab_applicant_path(applicant, tab: "ownership")

        expect(response.body).to include("Mr John Smith")
        expect(response.body).to include("75%+")
      end

      it "does not show a trace-chain button for an individual PSC" do
        post registry_lookup_applicant_path(applicant)

        get tab_applicant_path(applicant, tab: "ownership")

        expect(response.body).not_to include(I18n.t("applicants.tabs.ownership.registry_pscs_table.trace_chain"))
      end

      it "does not create duplicate principals when retried again" do
        post registry_lookup_applicant_path(applicant)

        expect { post registry_lookup_applicant_path(applicant) }
          .not_to change { applicant.kyc_principals.count }
      end
    end

    context "when signed in as psp_admin, and the lookup succeeds with a corporate PSC" do
      let(:fake_client) { instance_double(Registry::CompaniesHouseUkClient) }
      let(:fetch_result) do
        Registry::FetchResult.success(
          company_name: "Acme Ltd", status: "active", incorporated_on: Date.new(2020, 1, 1),
          directors: [], addresses: [],
          people_with_significant_control: [
            {
              name: "Example Holdings Ltd", kind: "corporate-entity-person-with-significant-control",
              natures_of_control: [ "ownership-of-shares-75-to-100-percent" ],
              notified_on: Date.new(2020, 1, 1), ceased_on: nil, nationality: nil,
              date_of_birth_month: nil, date_of_birth_year: nil,
              line1: nil, city: nil, postcode: nil, country: nil, registration_number: "99999999"
            }
          ]
        )
      end

      before do
        sign_in psp_admin
        allow(Registry::CompaniesHouseUkClient).to receive(:new).and_return(fake_client)
        allow(fake_client).to receive(:fetch).with(company_number: "12345678").and_return(fetch_result)
      end

      it "shows a trace-chain button for a corporate PSC" do
        post registry_lookup_applicant_path(applicant)

        get tab_applicant_path(applicant, tab: "ownership")

        expect(response.body).to include(I18n.t("applicants.tabs.ownership.registry_pscs_table.trace_chain"))
      end
    end

    context "when signed in as psp_admin, and the lookup fails" do
      let(:fake_client) { instance_double(Registry::CompaniesHouseUkClient) }
      let(:fetch_result) { Registry::FetchResult.failure(error_type: :unavailable) }

      before do
        sign_in psp_admin
        allow(Registry::CompaniesHouseUkClient).to receive(:new).and_return(fake_client)
        allow(fake_client).to receive(:fetch).with(company_number: "12345678").and_return(fetch_result)
      end

      it "redirects to show with a retry alert and persists nothing" do
        expect { post registry_lookup_applicant_path(applicant) }
          .not_to change { applicant.registry_profiles.count }

        expect(response).to redirect_to(applicant_path(applicant))
        expect(flash[:alert]).to be_present
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        post registry_lookup_applicant_path(applicant)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /applicants/:id/trace_psc_chain/:psc_id" do
    let(:applicant) { create(:applicant, company_number: "12345678", registry_jurisdiction: "gb", company_name: "Acme Ltd") }
    let(:registry_profile) { create(:registry_profile, applicant: applicant, company_number: "12345678") }
    let(:psc) do
      create(:registry_person_with_significant_control,
        registry_profile: registry_profile, name: "Intermediate Holdings Ltd",
        kind: "corporate-entity-person-with-significant-control", registration_number: "99999999")
    end

    context "when signed in as psp_admin, and the chain follower succeeds" do
      let(:fake_client) { instance_double(Registry::CompaniesHouseUkClient) }

      before do
        sign_in psp_admin
        psc
        allow(Registry::CompaniesHouseUkClient).to receive(:new).and_return(fake_client)
        allow(fake_client).to receive(:fetch).with(company_number: "99999999").and_return(
          Registry::FetchResult.success(
            company_name: "Intermediate Holdings Ltd", status: "active", incorporated_on: Date.new(2018, 1, 1),
            directors: [], addresses: [], people_with_significant_control: []
          )
        )
      end

      it "persists a new registry profile and redirects to show with a success notice" do
        expect { post trace_psc_chain_applicant_path(applicant, psc_id: psc.id) }
          .to change { applicant.registry_profiles.count }.by(1)

        expect(response).to redirect_to(applicant_path(applicant))
        expect(flash[:notice]).to be_present
      end
    end

    context "when signed in as psp_admin, and the chain follower fails" do
      before do
        sign_in psp_admin
        psc.update!(registration_number: nil)
      end

      it "redirects to show with an alert and persists nothing" do
        expect { post trace_psc_chain_applicant_path(applicant, psc_id: psc.id) }
          .not_to change { applicant.registry_profiles.count }

        expect(response).to redirect_to(applicant_path(applicant))
        expect(flash[:alert]).to be_present
      end
    end

    context "when signed in as psp_support" do
      before do
        sign_in psp_support
        psc
      end

      it "returns 403" do
        post trace_psc_chain_applicant_path(applicant, psc_id: psc.id)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /applicants/:id/edit" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "returns 200" do
        get edit_applicant_path(applicant_a)
        expect(response).to have_http_status(:ok)
      end

      it "disables sector editing once document collection has begun" do
        create(:onboarding_session, applicant: applicant_a, current_stage: :document_collection)

        get edit_applicant_path(applicant_a)

        expect(response.body).to include('id="applicant_sector"')
        expect(response.body).to include('disabled="disabled"')
        expect(response.body).to include("The business sector cannot be changed after document collection has begun.")
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        get edit_applicant_path(applicant_a)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "PATCH /applicants/:id" do
    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "updates and redirects to show" do
        patch applicant_path(applicant_a), params: {
          applicant: { contact_email: "updated@acme.com" }
        }
        expect(response).to redirect_to(applicant_path(applicant_a))
        expect(applicant_a.reload.contact_email).to eq("updated@acme.com")
      end

      it "updates the applicant sector" do
        patch applicant_path(applicant_a), params: { applicant: { sector: "gambling" } }

        expect(response).to redirect_to(applicant_path(applicant_a))
        expect(applicant_a.reload.sector).to eq("gambling")
      end

      it "rejects changing from general after document collection begins" do
        locked_applicant = create(:applicant, name: "Locked General Applicant", sector: :general)
        create(:onboarding_session, applicant: locked_applicant, current_stage: :document_collection)

        patch applicant_path(locked_applicant), params: { applicant: { sector: "crypto_exchange" } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Sector cannot be changed after document collection has begun")
        expect(locked_applicant.reload.sector).to eq("general")
      end

      it "rejects changing from a policy sector when a collection checklist already exists" do
        locked_applicant = create(:applicant, name: "Locked Policy Applicant", sector: :crypto_exchange)
        create(
          :onboarding_session,
          applicant: locked_applicant,
          current_stage: :jurisdictions,
          document_checklist: [ { "category" => "sector_policy" } ]
        )

        patch applicant_path(locked_applicant), params: { applicant: { sector: "general" } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Sector cannot be changed after document collection has begun")
        expect(locked_applicant.reload.sector).to eq("crypto_exchange")
      end

      it "rejects changing sector after a direct document upload without an onboarding session" do
        locked_applicant = create(:applicant, name: "Direct Upload Applicant", sector: :crypto_exchange)
        create(:kyc_document, applicant: locked_applicant)

        expect(locked_applicant.onboarding_session).to be_nil

        patch applicant_path(locked_applicant), params: { applicant: { sector: "general" } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Sector cannot be changed after document collection has begun")
        expect(locked_applicant.reload.sector).to eq("crypto_exchange")
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        patch applicant_path(applicant_a), params: { applicant: { name: "X" } }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "DELETE /applicants/:id" do
    let(:applicant) { create(:applicant) }

    around do |example|
      original = Rails.application.config.x.applicant_delete_enabled
      Rails.application.config.x.applicant_delete_enabled = true
      example.run
      Rails.application.config.x.applicant_delete_enabled = original
    end

    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "destroys the applicant and redirects to the index" do
        delete applicant_path(applicant)
        expect(response).to redirect_to(applicants_path)
        expect(Applicant.find_by(id: applicant.id)).to be_nil
      end

      it "redirects back to the applicant with an alert when it has a portal user" do
        create(:applicant_user, applicant: applicant)

        delete applicant_path(applicant)

        expect(response).to redirect_to(applicant_path(applicant))
        expect(flash[:alert]).to include("active portal user account")
        expect(Applicant.find_by(id: applicant.id)).to be_present
      end
    end

    context "when signed in as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        delete applicant_path(applicant)
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when signed in as merchant_admin" do
      before { sign_in merchant_admin }

      it "returns 403" do
        delete applicant_path(applicant)
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when the delete feature is disabled" do
      before do
        Rails.application.config.x.applicant_delete_enabled = false
        sign_in psp_admin
      end

      it "returns 404" do
        delete applicant_path(applicant)
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "GET /applicants/:id/tab/summary — portal users" do
    let(:applicant) { create(:applicant) }

    context "when signed in as psp_admin" do
      before { sign_in psp_admin }

      it "does not render a portal users table when there is none" do
        get tab_applicant_path(applicant, tab: "summary")
        expect(response.body).not_to include("Portal Users")
      end

      it "explains unmet Crypto Exchange policy evidence alongside entity results" do
        policy_applicant = create(:applicant, sector: :crypto_exchange)
        source_document = create(:kyc_document, applicant: policy_applicant, document_type: :group_structure_chart)
        create(
          :kyc_corporate_entity,
          applicant: policy_applicant,
          kyc_document: source_document,
          name: "Test Crypto Entity"
        )

        get tab_applicant_path(policy_applicant, tab: "summary")

        expect(response.body).to include("Test Crypto Entity")
        expect(response.body).to include("Wallet and custody infrastructure attestation")
        expect(response.body).to include("Upload an attestation describing the applicant")
        expect(response.body).to include("Unmet")
      end

      it "renders the portal user's email and a remove button when one exists" do
        applicant_user = create(:applicant_user, applicant: applicant, email: "jane@example.com")

        get tab_applicant_path(applicant, tab: "summary")

        expect(response.body).to include("Portal Users")
        expect(response.body).to include("jane@example.com")
        expect(response.body).to include(applicant_user_path(applicant_user))
      end

      it "renders an Unclassified badge instead of crashing when a document has no document_type (MH-271)" do
        create(:kyc_document, applicant: applicant, document_type: nil, status: :pending)

        get tab_applicant_path(applicant, tab: "summary")

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Unclassified")
      end
    end

    context "when signed in as psp_support (cannot remove portal users)" do
      before { sign_in psp_support }

      it "shows the portal user but not a remove button" do
        applicant_user = create(:applicant_user, applicant: applicant, email: "jane@example.com")

        get tab_applicant_path(applicant, tab: "summary")

        expect(response.body).to include("jane@example.com")
        expect(response.body).not_to include(applicant_user_path(applicant_user))
      end
    end
  end
end
