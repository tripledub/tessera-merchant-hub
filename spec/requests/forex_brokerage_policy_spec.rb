# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Forex Brokerage policy", type: :request do
  let(:psp_support) { create(:user, :psp_support) }
  let(:policy_titles) do
    [
      "Regulatory authorisation",
      "Client fund segregation evidence",
      "Capital adequacy evidence",
      "Negative balance protection policy"
    ]
  end

  before do
    Kyc::PolicyRegistry.instance = Kyc::PolicyRegistry.load!
    sign_in psp_support
  end

  it "drives the checklist and readiness from the deployed policy" do
    applicant = create(:applicant, sector: :forex_brokerage)
    session = create(:onboarding_session, applicant: applicant, current_stage: :document_collection)
    Onboarding::DocumentCollectionService.generate_checklist(session)

    get transcript_path(session)

    expect(response).to have_http_status(:ok)
    expect(rendered_policy_statuses).to eq(policy_titles.index_with { "Outstanding" })
    expect(Kyc::Compliance::ReadinessAssessment.for(applicant).policy_results).to all(be_unmet)

    create_policy_documents(applicant)

    get transcript_path(session)

    expect(policy_items(session).map { |item| item["label"] }).to eq(policy_titles)
    expect(policy_items(session)).to all(include("received" => true))
    expect(rendered_policy_statuses).to eq(policy_titles.index_with { "Received" })
    expect(Kyc::Compliance::ReadinessAssessment.for(applicant).policy_results).to all(be_met)
  end

  it "does not apply Forex Brokerage requirements to another sector" do
    applicant = create(:applicant, sector: :general)
    session = create(:onboarding_session, applicant: applicant, current_stage: :document_collection)
    Onboarding::DocumentCollectionService.generate_checklist(session)

    get transcript_path(session)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(*policy_titles)
    expect(Kyc::Compliance::ReadinessAssessment.for(applicant).policy_results).to be_empty
  end

  def create_policy_documents(applicant)
    %i[
      regulatory_authorisation
      client_fund_segregation_evidence
      capital_adequacy_evidence
      negative_balance_protection_policy
    ].each do |document_type|
      create(:kyc_document, applicant: applicant, document_type: document_type,
                            classification_status: :confirmed, status: :complete)
    end
  end

  def policy_items(session)
    Onboarding::DocumentCollectionService.received_documents(session)
      .select { |item| item["category"] == "sector_policy" }
  end

  def rendered_policy_statuses
    policy_titles.index_with { |title| rendered_checklist_status(title) }
  end

  def rendered_checklist_status(title)
    page = Nokogiri::HTML(response.body)
    checklist = page.at_css("section[aria-labelledby='documents-heading']")
    label = checklist.xpath(".//span").find { |node| node.text.strip == title }
    return if label.nil?

    label.parent.xpath("./span").last.text.strip
  end
end
