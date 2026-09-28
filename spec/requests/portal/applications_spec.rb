# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Portal application shell", type: :request do
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
          registered_address_attributes: {
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
end
