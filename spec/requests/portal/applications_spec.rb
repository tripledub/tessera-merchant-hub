# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Portal application shell", type: :request do
  it "rate limits repeated application saves for the authenticated applicant" do
    applicant_user = create(:applicant_user)
    create(:onboarding_application, applicant: applicant_user.applicant)
    sign_in applicant_user, scope: :applicant_user
    store = Portal::ApplicationsController.portal_rate_limit_store
    store.write("rate-limit:portal/applications:#{applicant_user.applicant_id}", 60, expires_in: 1.minute)

    patch portal_application_path, params: { step: "company", onboarding_application: {} }

    expect(response).to have_http_status(:too_many_requests)
  end

  it "requires applicant authentication" do
    get portal_application_path

    expect(response).to redirect_to(new_applicant_user_session_path)
  end

  it "creates a draft application for the authenticated applicant" do
    applicant_user = create(:applicant_user)
    sign_in applicant_user, scope: :applicant_user

    expect { get portal_application_path }.to change(OnboardingApplication, :count).by(1)

    application = OnboardingApplication.last
    expect(application).to have_attributes(applicant: applicant_user.applicant, status: "draft")
    expect(response.body).to include("Company details", "Review and submit")
    page = Capybara.string(response.body)
    expect(page).to have_link("Company details")
    expect(page).to have_no_link("Review and submit")
  end

  it "saves progress and resumes it after logout and login" do
    applicant_user = create(:applicant_user)
    application = create(:onboarding_application, applicant: applicant_user.applicant)
    sign_in applicant_user, scope: :applicant_user

    patch portal_application_path, params: company_details_params(application)
    expect(response).to redirect_to(portal_application_path(step: "fulfilment"))

    delete destroy_applicant_user_session_path
    sign_in applicant_user, scope: :applicant_user
    get portal_application_path

    expect(response).to redirect_to(portal_application_path(step: "fulfilment"))
    expect(application.reload.completed_steps).to eq([ "company" ])
  end

  it "renders the company fields with previously saved shared-domain values" do
    applicant_user = create(:applicant_user)
    application = create(
      :onboarding_application,
      applicant: applicant_user.applicant,
      business_model_description: "Existing business description",
      operating_licence: "None required"
    )
    create(:applicant_domain, applicant: applicant_user.applicant, name: "existing.example")
    create(:address, :business, :primary, addressable: applicant_user.applicant, line1: "1 Existing Street")
    create(:address, :primary, addressable: applicant_user.applicant, type: "Address::Trading", line1: "2 Trading Road")
    sign_in applicant_user, scope: :applicant_user

    get portal_application_path(step: "company")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(
      application.applicant.company_name,
      "Existing business description",
      "existing.example",
      "1 Existing Street",
      "2 Trading Road"
    )
  end

  it "labels the address groups and defaults the same-as-registered option to checked for a new applicant" do
    applicant_user = create(:applicant_user)
    create(:onboarding_application, applicant: applicant_user.applicant)
    sign_in applicant_user, scope: :applicant_user

    get portal_application_path(step: "company")

    expect(response).to have_http_status(:ok)
    page = Capybara.string(response.body)
    expect(page).to have_css("legend", text: "Registered address")
    expect(page).to have_css("legend", text: "Trading address")
    checkbox = page.find_field("onboarding_application[trading_address_same_as_registered]")
    expect(checkbox).to be_checked
  end

  it "mirrors the registered address onto the trading address and does not create a duplicate record when marked same" do
    applicant_user = create(:applicant_user)
    application = create(:onboarding_application, applicant: applicant_user.applicant)
    sign_in applicant_user, scope: :applicant_user
    params = company_details_params(application)
    params[:onboarding_application][:trading_address_same_as_registered] = "1"
    params[:onboarding_application][:applicant_attributes][:trading_address_attributes] =
      { line1: "", city: "", postcode: "", country: "" }

    expect { patch portal_application_path, params: params }.to change(Address, :count).by(2)

    applicant = applicant_user.applicant.reload
    expect(applicant.trading_address).to have_attributes(
      line1: "1 Test Street", city: "Testford", postcode: "TE1 1ST", country: "United Kingdom"
    )

    resubmit_params = company_details_params(application)
    resubmit_params[:onboarding_application][:trading_address_same_as_registered] = "1"
    expect { patch portal_application_path, params: resubmit_params }.not_to change(Address, :count)
  end

  it "preserves a genuinely different trading address when same-as-registered is not selected" do
    applicant_user = create(:applicant_user)
    application = create(:onboarding_application, applicant: applicant_user.applicant)
    sign_in applicant_user, scope: :applicant_user
    params = company_details_params(application)

    patch portal_application_path, params: params

    expect(response).to redirect_to(portal_application_path(step: "fulfilment"))
    applicant = applicant_user.applicant.reload
    expect(applicant.trading_address).to have_attributes(line1: "2 Example Road", city: "Testford")
    expect(applicant.primary_business_address).to have_attributes(line1: "1 Test Street")
  end

  it "applies dark-mode contrast tokens to the registered and trading address fieldsets" do
    applicant_user = create(:applicant_user)
    create(:onboarding_application, applicant: applicant_user.applicant)
    sign_in applicant_user, scope: :applicant_user

    get portal_application_path(step: "company")

    expect(response).to have_http_status(:ok)
    page = Capybara.string(response.body)
    fieldsets = page.all("fieldset.card")
    expect(fieldsets.size).to eq(2)
    fieldsets.each { |fieldset| expect(fieldset["class"]).to include("card") } # theme-aware surface: dark:bg-gray-900 dark:border-gray-800
    page.all("fieldset.card legend").each { |legend| expect(legend["class"]).to include("dark:text-white/90") }
  end

  it "returns validation errors against the company step without persisting partial answers" do
    applicant_user = create(:applicant_user)
    application = create(:onboarding_application, applicant: applicant_user.applicant)
    sign_in applicant_user, scope: :applicant_user
    params = company_details_params(application)
    params[:onboarding_application][:business_model_description] = ""

    patch portal_application_path, params: params

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Business model description can&#39;t be blank")
    expect(application.reload.current_step).to eq("company")
  end

  it "shows a website validation error against the affected repeated item" do
    applicant_user = create(:applicant_user)
    application = create(:onboarding_application, applicant: applicant_user.applicant)
    sign_in applicant_user, scope: :applicant_user
    params = company_details_params(application)
    params[:onboarding_application][:applicant_attributes][:applicant_domains_attributes]["0"][:name] = "not a domain"

    patch portal_application_path, params: params

    expect(response).to have_http_status(:unprocessable_content)
    website_item = Capybara.string(response.body).find("[data-repeatable-fields-target='item']")
    expect(website_item).to have_field(with: "not a domain")
    expect(website_item).to have_css(".form-error", text: "Name is invalid")
  end

  it "accepts the company step with no website domain, for applicants without one (e.g. MOTO)" do
    applicant_user = create(:applicant_user)
    application = create(:onboarding_application, applicant: applicant_user.applicant)
    sign_in applicant_user, scope: :applicant_user
    params = company_details_params(application)
    params[:onboarding_application][:applicant_attributes][:applicant_domains_attributes]["0"][:name] = ""

    patch portal_application_path, params: params

    expect(response).to redirect_to(portal_application_path(step: "fulfilment"))
    expect(application.applicant.reload.applicant_domains).to be_empty
  end

  it "renders saved fulfilment answers and conditionally exposes deposit fields" do
    applicant_user = create(:applicant_user)
    application = fulfilment_application_for(
      applicant_user,
      delivery_over_seven_days: false,
      full_payment_before_delivery: true,
      takes_deposits: true,
      deposit_percentage: 30,
      remaining_balance_due: "On dispatch",
      service_requirements: "Hosted checkout",
      integration_type: "API"
    )
    sign_in applicant_user, scope: :applicant_user

    get portal_application_path(step: "fulfilment")

    expect(response).to have_http_status(:ok)
    page = Capybara.string(response.body)
    expect(page).to have_checked_field("onboarding_application[takes_deposits]", with: "true")
    expect(page).to have_field("onboarding_application[deposit_percentage]", with: "30.0", disabled: false)
    expect(page).to have_field("onboarding_application[remaining_balance_due]", with: "On dispatch", disabled: false)
    expect(response.body).to include("conditional-fields#toggle", "Hosted checkout", "API")
  end

  it "does not require or submit deposit details when deposits are not taken" do
    applicant_user = create(:applicant_user)
    application = fulfilment_application_for(applicant_user)
    sign_in applicant_user, scope: :applicant_user

    patch portal_application_path, params: {
      step: "fulfilment",
      onboarding_application: {
        delivery_over_seven_days: "false",
        full_payment_before_delivery: "true",
        takes_deposits: "false",
        service_requirements: "Hosted checkout",
        integration_type: "API"
      }
    }

    expect(response).to redirect_to(portal_application_path(step: "currencies"))
    expect(application.reload).to have_attributes(takes_deposits: false, deposit_percentage: nil, remaining_balance_due: nil)
  end

  it "renders fulfilment validation errors without advancing" do
    applicant_user = create(:applicant_user)
    application = fulfilment_application_for(applicant_user)
    sign_in applicant_user, scope: :applicant_user

    patch portal_application_path, params: {
      step: "fulfilment",
      onboarding_application: {
        delivery_over_seven_days: "true",
        full_payment_before_delivery: "false",
        takes_deposits: "true",
        deposit_percentage: "",
        remaining_balance_due: "",
        service_requirements: "Hosted checkout",
        integration_type: "API"
      }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Deposit percentage can&#39;t be blank", "Remaining balance due can&#39;t be blank")
    expect(application.reload.current_step).to eq("fulfilment")
  end

  it "saves repeatable processing and settlement currencies" do
    applicant_user = create(:applicant_user)
    application = currency_application_for(applicant_user)
    sign_in applicant_user, scope: :applicant_user

    patch portal_application_path, params: {
      step: "currencies",
      onboarding_application: {
        processing_currencies_attributes: { "0" => { code: "gbp" }, "1" => { code: "eur" } },
        settlement_currencies_attributes: { "0" => { code: "usd" } }
      }
    }

    expect(response).to redirect_to(portal_application_path(step: "processing"))
    expect(application.processing_currencies.pluck(:code)).to contain_exactly("GBP", "EUR")
    expect(application.settlement_currencies.pluck(:code)).to contain_exactly("USD")
  end

  it "restores currencies and renders nested format errors" do
    applicant_user = create(:applicant_user)
    application = currency_application_for(applicant_user)
    application.processing_currencies.create!(code: "GBP")
    application.settlement_currencies.create!(code: "EUR")
    sign_in applicant_user, scope: :applicant_user

    get portal_application_path(step: "currencies")
    expect(response.body).to include("GBP", "EUR")

    patch portal_application_path, params: {
      step: "currencies",
      onboarding_application: {
        processing_currencies_attributes: { "0" => { code: "invalid" } },
        settlement_currencies_attributes: { "0" => { id: application.settlement_currencies.first.id, code: "EUR" } }
      }
    }

    expect(response).to have_http_status(:unprocessable_content)
    items = Capybara.string(response.body).all("[data-repeatable-fields-target='item']")
    item = items.find { |candidate| candidate.has_field?(with: "INVALID") }
    expect(item).to have_field(with: "INVALID")
    expect(item).to have_css(".form-error", text: "Code is invalid")
  end

  it "renders saved processing history and its conditional acquirer field" do
    applicant_user = create(:applicant_user)
    processing_application_for(
      applicant_user,
      currently_accepts_card_payments: true,
      current_acquirer: "Specimen Bank"
    )
    sign_in applicant_user, scope: :applicant_user

    get portal_application_path(step: "processing")

    expect(response).to have_http_status(:ok)
    page = Capybara.string(response.body)
    expect(page).to have_checked_field("onboarding_application[currently_accepts_card_payments]", with: "true")
    expect(page).to have_field("onboarding_application[current_acquirer]", with: "Specimen Bank", disabled: false)
    expect(response.body).to include("conditional-fields#toggle")
  end

  it "saves processing history through the controller and advances" do
    applicant_user = create(:applicant_user)
    application = processing_application_for(applicant_user)
    sign_in applicant_user, scope: :applicant_user

    patch portal_application_path, params: {
      step: "processing",
      onboarding_application: {
        currently_accepts_card_payments: "true",
        current_acquirer: "Specimen Bank"
      }
    }

    expect(response).to redirect_to(portal_application_path(step: "payments"))
    expect(application.reload).to have_attributes(
      currently_accepts_card_payments: true,
      current_acquirer: "Specimen Bank",
      current_step: "payments"
    )
  end

  it "renders processing validation errors without advancing" do
    applicant_user = create(:applicant_user)
    application = processing_application_for(applicant_user)
    sign_in applicant_user, scope: :applicant_user

    patch portal_application_path, params: {
      step: "processing",
      onboarding_application: {
        currently_accepts_card_payments: "true",
        current_acquirer: ""
      }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Current acquirer can&#39;t be blank")
    expect(application.reload.current_step).to eq("processing")
  end

  it "rejects processing history before the applicant reaches that step" do
    applicant_user = create(:applicant_user)
    application = currency_application_for(applicant_user)
    sign_in applicant_user, scope: :applicant_user

    patch portal_application_path, params: {
      step: "processing",
      onboarding_application: {
        currently_accepts_card_payments: "true",
        current_acquirer: "Should not persist"
      }
    }

    expect(response).to redirect_to(portal_application_path(step: "currencies"))
    expect(application.reload).to have_attributes(
      current_step: "currencies",
      currently_accepts_card_payments: nil,
      current_acquirer: nil
    )
  end

  it "renders saved shopping-cart and recurring-payment answers" do
    applicant_user = create(:applicant_user)
    payment_application_for(
      applicant_user,
      uses_shopping_cart: true,
      shopping_cart_provider: "Specimen Cart",
      takes_recurring_payments: true,
      sends_recurring_payment_receipts: true,
      sends_recurring_payment_advance_notifications: false
    )
    sign_in applicant_user, scope: :applicant_user

    get portal_application_path(step: "payments")

    page = Capybara.string(response.body)
    expect(page).to have_checked_field("onboarding_application[uses_shopping_cart]", with: "true")
    expect(page).to have_field("onboarding_application[shopping_cart_provider]", with: "Specimen Cart", disabled: false)
    expect(page).to have_checked_field("onboarding_application[takes_recurring_payments]", with: "true")
    expect(page).to have_checked_field("onboarding_application[sends_recurring_payment_receipts]", with: "true")
    expect(page).to have_checked_field(
      "onboarding_application[sends_recurring_payment_advance_notifications]", with: "false"
    )
  end

  it "saves payment details and advances to descriptor details" do
    applicant_user = create(:applicant_user)
    application = payment_application_for(applicant_user)
    sign_in applicant_user, scope: :applicant_user

    patch portal_application_path, params: {
      step: "payments",
      onboarding_application: {
        uses_shopping_cart: "false",
        takes_recurring_payments: "true",
        sends_recurring_payment_receipts: "true",
        sends_recurring_payment_advance_notifications: "false"
      }
    }

    expect(response).to redirect_to(portal_application_path(step: "descriptor"))
    expect(application.reload).to have_attributes(
      uses_shopping_cart: false,
      shopping_cart_provider: nil,
      takes_recurring_payments: true,
      sends_recurring_payment_receipts: true,
      sends_recurring_payment_advance_notifications: false
    )
  end

  it "renders, validates and saves descriptor details" do
    applicant_user = create(:applicant_user)
    application = descriptor_application_for(applicant_user, descriptor: "SAVED SHOP")
    sign_in applicant_user, scope: :applicant_user

    get portal_application_path(step: "descriptor")
    expect(response.body).to include("SAVED SHOP")

    patch portal_application_path, params: {
      step: "descriptor",
      onboarding_application: {
        descriptor: "SPECIMEN SHOP",
        descriptor_company_number: "12345678",
        descriptor_company_city: "Testford"
      }
    }

    expect(response).to redirect_to(portal_application_path(step: "pricing"))
    expect(application.reload).to have_attributes(
      descriptor: "SPECIMEN SHOP",
      descriptor_company_number: "12345678",
      descriptor_company_city: "Testford"
    )
  end

  it "renders descriptor validation errors without persisting partial answers" do
    applicant_user = create(:applicant_user)
    application = descriptor_application_for(applicant_user)
    sign_in applicant_user, scope: :applicant_user

    patch portal_application_path, params: {
      step: "descriptor",
      onboarding_application: { descriptor: "PARTIAL", descriptor_company_number: "", descriptor_company_city: "" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Descriptor company number can&#39;t be blank")
    expect(application.reload).to have_attributes(current_step: "descriptor", descriptor: nil)
  end

  it "rejects fulfilment answers before the applicant reaches that step" do
    applicant_user = create(:applicant_user)
    application = create(:onboarding_application, applicant: applicant_user.applicant, current_step: "company")
    sign_in applicant_user, scope: :applicant_user

    patch portal_application_path, params: {
      step: "fulfilment",
      onboarding_application: {
        delivery_over_seven_days: "false",
        full_payment_before_delivery: "true",
        takes_deposits: "false",
        service_requirements: "Should not persist",
        integration_type: "API"
      }
    }

    expect(response).to redirect_to(portal_application_path(step: "company"))
    expect(application.reload).to have_attributes(
      current_step: "company",
      service_requirements: nil,
      integration_type: nil
    )
  end

  it "lets an applicant revisit a completed step without changing saved progress" do
    applicant_user = create(:applicant_user)
    application = create(
      :onboarding_application,
      applicant: applicant_user.applicant,
      current_step: "processing",
      completed_steps: %w[company fulfilment currencies]
    )
    sign_in applicant_user, scope: :applicant_user

    get portal_application_path(step: "company")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Company details")
    expect(application.reload.current_step).to eq("processing")
  end

  it "redirects attempts to visit a future step back to the current step" do
    applicant_user = create(:applicant_user)
    create(:onboarding_application, applicant: applicant_user.applicant, current_step: "company")
    sign_in applicant_user, scope: :applicant_user

    get portal_application_path(step: "review")

    expect(response).to redirect_to(portal_application_path(step: "company"))
  end

  it "does not expose another applicant's application through an identifier" do
    applicant_user = create(:applicant_user)
    other_application = create(:onboarding_application)
    sign_in applicant_user, scope: :applicant_user

    get portal_application_path(id: other_application.id)

    own_application = applicant_user.applicant.reload.onboarding_application
    expect(response).to have_http_status(:ok)
    expect(own_application).to be_present
    expect(response.body).not_to include(other_application.id)
  end

  it "returns not found for an unknown step" do
    applicant_user = create(:applicant_user)
    sign_in applicant_user, scope: :applicant_user

    get portal_application_path(step: "unknown")

    expect(response).to have_http_status(:not_found)
  end

  it "renders and saves repeatable directors and beneficial owners" do
    applicant_user = create(:applicant_user)
    application = principals_application_for(applicant_user)
    sign_in applicant_user, scope: :applicant_user

    get portal_application_path(step: "principals")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Add director or beneficial owner")

    patch portal_application_path,
      params: principal_params(application, role: "director_and_psc", ownership_percentage: "51.25")

    expect(response).to redirect_to(portal_application_path(step: "review"))
    expect(application.applicant.kyc_principals.find_by(name: "Morgan Owner")).to have_attributes(
      role: "director_and_psc", ownership_percentage: 51.25, source: "applicant_declared"
    )
  end

  it "identifies the affected repeated person when validation fails" do
    applicant_user = create(:applicant_user)
    application = principals_application_for(applicant_user)
    sign_in applicant_user, scope: :applicant_user

    patch portal_application_path,
      params: principal_params(application, role: "psc", ownership_percentage: "")

    expect(response).to have_http_status(:unprocessable_content)
    person = Capybara.string(response.body).find("[data-repeatable-fields-target='item']")
    expect(person).to have_field(with: "Morgan Owner")
    expect(person).to have_css(".form-error", text: "Ownership percentage can't be blank")
    expect(application.reload.current_step).to eq("principals")
  end

  it "shows the registered address and a same-as-registered notice when the trading address matches" do
    applicant_user = create(:applicant_user)
    review_application_for(applicant_user)
    sign_in applicant_user, scope: :applicant_user

    get portal_application_path(step: "review")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("1 Test Street, London, EC1A 1BB, United Kingdom")
    page = Capybara.string(response.body)
    expect(page).to have_css("dt", text: "Registered address")
    expect(page).to have_css("dt", text: "Trading address")
    expect(page).to have_css("dd", text: "Same as registered address")
  end

  it "shows a genuinely different trading address distinctly on the review page" do
    applicant_user = create(:applicant_user)
    application = review_application_for(applicant_user)
    application.applicant.trading_address.update!(line1: "2 Different Road", city: "Manchester")
    sign_in applicant_user, scope: :applicant_user

    get portal_application_path(step: "review")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("1 Test Street, London, EC1A 1BB, United Kingdom")
    expect(response.body).to include("2 Different Road, Manchester, EC1A 1BB, United Kingdom")
    expect(response.body).not_to include("Same as registered address")
  end

  it "reviews supplied information by section and submits a complete application" do
    applicant_user = create(:applicant_user)
    application = review_application_for(applicant_user)
    sign_in applicant_user, scope: :applicant_user

    get portal_application_path(step: "review")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Company details", "Fulfilment and service", "Morgan Owner", "Edit")

    patch portal_application_path, params: { step: "review" }

    expect(response).to redirect_to(portal_application_path(step: "review"))
    application.reload
    expect(application).to be_submitted
    expect(application.submitted_at).to be_present
    expect(application.completed_steps).to include("review")

    get portal_application_path(step: "review")
    expect(response.body).to include('aria-valuenow="100"')
  end

  it "applies dark-mode contrast tokens to the review page sections and values" do
    applicant_user = create(:applicant_user)
    application = review_application_for(applicant_user)
    sign_in applicant_user, scope: :applicant_user

    get portal_application_path(step: "review")

    expect(response).to have_http_status(:ok)
    page = Capybara.string(response.body)
    sections = page.all("section.card")
    expect(sections.size).to be >= 2
    sections.each { |section| expect(section["class"]).to include("card") } # theme-aware surface: dark:bg-gray-900 dark:border-gray-800
    page.all("section.card h3").each { |heading| expect(heading["class"]).to include("dark:text-white/90") }
    page.all("section.card dt").each { |label| expect(label["class"]).to include("dark:text-gray-400") }
    page.all("section.card dd").each { |value| expect(value["class"]).to include("dark:text-white/90") }

    patch portal_application_path, params: { step: "review" }
    expect(response).to redirect_to(portal_application_path(step: "review"))

    get portal_application_path(step: "review")
    submitted_notice = Capybara.string(response.body).find("p.text-green-700")
    expect(submitted_notice["class"]).to include("dark:text-green-400")
  end

  it "highlights missing required information and prevents submission" do
    applicant_user = create(:applicant_user)
    application = review_application_for(applicant_user)
    application.update_column(:descriptor, nil)
    sign_in applicant_user, scope: :applicant_user

    patch portal_application_path, params: { step: "review" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Descriptor can&#39;t be blank", "Missing")
    expect(application.reload).to be_draft
  end

  it "wires client-side validation onto every non-repeatable onboarding step form" do
    steps_setup = {
      "company" => ->(applicant_user) { create(:onboarding_application, applicant: applicant_user.applicant) },
      "descriptor" => method(:descriptor_application_for),
      "fulfilment" => method(:fulfilment_application_for),
      "processing" => method(:processing_application_for),
      "payments" => method(:payment_application_for)
    }

    steps_setup.each do |step, build_application|
      applicant_user = create(:applicant_user)
      build_application.call(applicant_user)
      sign_in applicant_user, scope: :applicant_user

      get portal_application_path(step: step)

      page = Capybara.string(response.body)
      form = page.find("form[action='#{portal_application_path}']")
      expect(form["data-controller"]).to include("form-validation")
      expect(form["data-action"]).to include("form-validation#submitForm")

      delete destroy_applicant_user_session_path
    end
  end

  def company_details_params(application)
    applicant = application.applicant
    {
      step: "company",
      onboarding_application: {
        business_model_description: "A specimen business model",
        operating_licence: "None required",
        applicant_attributes: {
          id: applicant.id,
          company_name: applicant.company_name,
          company_number: "12345678",
          sector: applicant.sector,
          primary_business_address_attributes: {
            line1: "1 Test Street", city: "Testford", postcode: "TE1 1ST", country: "United Kingdom"
          },
          trading_address_attributes: {
            line1: "2 Example Road", city: "Testford", postcode: "TE1 2ST", country: "United Kingdom"
          },
          applicant_domains_attributes: { "0" => { name: "specimen.example" } }
        }
      }
    }
  end

  def fulfilment_application_for(applicant_user, **attributes)
    create(
      :onboarding_application,
      applicant: applicant_user.applicant,
      current_step: "fulfilment",
      completed_steps: [ "company" ],
      **attributes
    )
  end

  def currency_application_for(applicant_user)
    create(
      :onboarding_application,
      applicant: applicant_user.applicant,
      current_step: "currencies",
      completed_steps: %w[company fulfilment]
    )
  end

  def processing_application_for(applicant_user, **attributes)
    create(
      :onboarding_application,
      applicant: applicant_user.applicant,
      current_step: "processing",
      completed_steps: %w[company fulfilment currencies],
      **attributes
    )
  end

  def payment_application_for(applicant_user, **attributes)
    create(
      :onboarding_application,
      applicant: applicant_user.applicant,
      current_step: "payments",
      completed_steps: %w[company fulfilment currencies processing],
      **attributes
    )
  end

  def descriptor_application_for(applicant_user, **attributes)
    create(
      :onboarding_application,
      applicant: applicant_user.applicant,
      current_step: "descriptor",
      completed_steps: %w[company fulfilment currencies processing payments],
      **attributes
    )
  end

  def principals_application_for(applicant_user)
    create(
      :onboarding_application,
      applicant: applicant_user.applicant,
      current_step: "principals",
      completed_steps: %w[company fulfilment currencies processing payments descriptor pricing volumes countries]
    )
  end

  def principal_params(application, role:, ownership_percentage:)
    {
      step: "principals",
      onboarding_application: {
        applicant_attributes: {
          id: application.applicant_id,
          kyc_principals_attributes: {
            "0" => {
              name: "Morgan Owner", date_of_birth: "1980-01-02", email: "morgan@example.com",
              role: role, ownership_percentage: ownership_percentage
            }
          }
        }
      }
    }
  end

  def review_application_for(applicant_user)
    applicant = applicant_user.applicant
    applicant.update!(company_number: "12345678")
    create(:address, :business, :primary, addressable: applicant)
    create(:address, :primary, type: "Address::Trading", addressable: applicant)
    create(:applicant_domain, applicant: applicant)
    create(:kyc_principal, applicant: applicant, source: :applicant_declared,
      name: "Morgan Owner", date_of_birth: Date.new(1980, 1, 2), email: "owner@example.com")
    application = create(:onboarding_application, applicant: applicant, current_step: "review",
      completed_steps: OnboardingApplication::STEPS - [ "review" ], **review_required_answers)
    application.processing_currencies.create!(code: "GBP")
    application.settlement_currencies.create!(code: "GBP")
    application
  end

  def review_required_answers
    {
      business_model_description: "Online retail", operating_licence: "None required",
      delivery_over_seven_days: false, full_payment_before_delivery: true, takes_deposits: false,
      service_requirements: "Card payments", integration_type: "API",
      currently_accepts_card_payments: false, uses_shopping_cart: false, takes_recurring_payments: false,
      descriptor: "SPECIMEN", descriptor_company_number: "12345678", descriptor_company_city: "London"
    }
  end
end
