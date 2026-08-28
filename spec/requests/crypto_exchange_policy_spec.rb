# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Crypto Exchange policy", type: :request do
  let(:psp_support) { create(:user, :psp_support) }
  let(:policy_titles) do
    [ "VASP registration", "Wallet and custody infrastructure attestation" ]
  end

  before do
    Kyc::PolicyRegistry.instance = Kyc::PolicyRegistry.load!
    sign_in psp_support
  end

  it "drives the rendered checklist, readiness, and completeness from the deployed policy" do
    applicant = create(:applicant, sector: :crypto_exchange)
    session = create(:onboarding_session, applicant: applicant, current_stage: :document_collection)
    Onboarding::DocumentCollectionService.generate_checklist(session)

    get transcript_path(session)

    expect(response).to have_http_status(:ok)
    expect(rendered_policy_statuses).to eq(policy_titles.index_with { "Outstanding" })
    expect(Kyc::Compliance::ReadinessAssessment.for(applicant)).not_to be_compliant
    expect(compliance_dimension_for(applicant)).to have_attributes(numerator: 0, denominator: 2)

    create_policy_documents(applicant)

    get transcript_path(session)

    expect(policy_items(session).map { |item| item["label"] }).to eq(policy_titles)
    expect(policy_items(session)).to all(include("received" => true))
    expect(rendered_policy_statuses).to eq(policy_titles.index_with { "Received" })
    readiness = Kyc::Compliance::ReadinessAssessment.for(applicant)
    expect(readiness.policy_results).to all(be_met)
    expect(readiness).to be_compliant
    expect(compliance_dimension_for(applicant)).to have_attributes(numerator: 2, denominator: 2)
  end

  it "does not render Crypto Exchange requirements for a general applicant" do
    applicant = create(:applicant, sector: :general)
    session = create(:onboarding_session, applicant: applicant, current_stage: :document_collection)
    Onboarding::DocumentCollectionService.generate_checklist(session)

    get transcript_path(session)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("VASP registration", "Wallet and custody infrastructure attestation")
    expect(Kyc::Compliance::ReadinessAssessment.for(applicant).policy_results).to be_empty
    expect(compliance_dimension_for(applicant)).to have_attributes(numerator: 0, denominator: 0)
  end

  def compliance_dimension_for(applicant)
    Kyc::CompletenessCalculator.for(applicant).dimensions.find { |dimension| dimension.key == :compliance_rules }
  end

  def create_policy_documents(applicant)
    %i[vasp_registration wallet_custody_infrastructure_attestation].each do |document_type|
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
