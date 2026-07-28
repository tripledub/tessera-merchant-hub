# frozen_string_literal: true

require "rails_helper"

# MH-198: end-to-end coverage of document-validity integration into the
# staff-facing Applicant overview tab (which renders both
# Kyc::CompletenessCalculator — "Applicant collection"/document completeness
# — and Kyc::Compliance::ReadinessAssessment — staff compliance review) for
# every validity outcome state, plus the out-of-rollout case, and proves
# repeated page loads never create duplicate Kyc::DocumentValidityAssessment
# rows.
RSpec.describe "Applicant overview — document validity integration", type: :request do
  let_it_be(:psp_admin) { create(:user, :psp_admin) }

  let(:applicant) { create(:applicant) }
  let(:source_document) { create(:kyc_document, applicant: applicant) }
  let(:entity) do
    create(:kyc_corporate_entity, applicant: applicant, kyc_document: source_document,
                                  entity_type: :corporate, name: "Northwind Holdings Ltd")
  end

  def validity_dates_for(normalized:, confidence: 0.95)
    { "raw" => normalized, "normalized" => normalized, "confidence" => confidence, "provenance" => "ai_extraction" }
  end

  def get_overview
    get tab_applicant_path(applicant, tab: "overview")
  end

  def create_certificate_of_incorporation
    create(:kyc_document, applicant: applicant, corporate_entity: entity,
           document_type: :certificate_of_incorporation)
  end

  before do
    # Kyc::Compliance::RuleRegistry is a process-wide singleton that several
    # other specs (readiness_assessment_spec, rule_runner_spec,
    # compliance_readiness_presenter_spec) call .reset! on and repopulate
    # with example-local stub rules — a stub's registration outlives its own
    # example (stub_const reverts the constant, not the RuleRegistry array),
    # so with random spec ordering the registry the production code sees at
    # this point can be in whatever state the last such spec left it in.
    # This integration spec exercises the real ReadinessAssessment/RuleRunner
    # path end-to-end, so it must not depend on run order to see the actual
    # production rule set — pin it explicitly.
    Kyc::Compliance::RuleRegistry.reset!
    [ Kyc::Compliance::Rules::CorporateDocumentation, Kyc::Compliance::Rules::NomineeDocumentation,
      Kyc::Compliance::Rules::UboDocumentRequirements, Kyc::Compliance::Rules::DocumentValidity ].each do |rule_class|
      Kyc::Compliance::RuleRegistry.register(rule_class)
    end

    sign_in psp_admin
    Kyc::DocumentValidityPolicy.publish!(
      document_type: "passport", effective_from: Date.new(2020, 1, 1),
      mode: :expires, required_dates: [ "expiry" ], warning_thresholds: [ 90, 30 ]
    )
    Kyc::DocumentValidityPolicy.publish!(
      document_type: "utility_bill", effective_from: Date.new(2020, 1, 1),
      mode: :freshness, required_dates: [ "issued" ], warning_thresholds: [], max_age_months: 3
    )
  end

  context "with a valid document" do
    it "counts toward completeness and readiness is compliant" do
      entity # ensure created
      create_certificate_of_incorporation
      create(:kyc_document, applicant: applicant, corporate_entity: entity, document_type: :passport,
             classification_status: :confirmed, status: :complete,
             validity_dates: { "expiry" => validity_dates_for(normalized: (applicant.validity_reference_date + 2.years).iso8601) })

      get_overview
      expect(response).to have_http_status(:ok)

      extraction = Kyc::CompletenessCalculator.for(applicant).dimensions.find { |d| d.key == :extraction }
      expect(extraction.numerator).to eq(1)

      readiness = Kyc::Compliance::ReadinessAssessment.for(applicant)
      expect(readiness).to be_compliant
    end
  end

  context "with an expiring_soon document" do
    it "counts toward completeness and readiness is compliant" do
      entity
      create_certificate_of_incorporation
      create(:kyc_document, applicant: applicant, corporate_entity: entity, document_type: :passport,
             classification_status: :confirmed, status: :complete,
             validity_dates: { "expiry" => validity_dates_for(normalized: (applicant.validity_reference_date + 10).iso8601) })

      get_overview
      expect(response).to have_http_status(:ok)

      extraction = Kyc::CompletenessCalculator.for(applicant).dimensions.find { |d| d.key == :extraction }
      expect(extraction.numerator).to eq(1)

      readiness = Kyc::Compliance::ReadinessAssessment.for(applicant)
      expect(readiness).to be_compliant
    end
  end

  context "with an expired document" do
    it "does not count toward completeness and readiness is not compliant (unmet)" do
      entity
      create_certificate_of_incorporation
      create(:kyc_document, applicant: applicant, corporate_entity: entity, document_type: :passport,
             classification_status: :confirmed, status: :complete,
             validity_dates: { "expiry" => validity_dates_for(normalized: (applicant.validity_reference_date - 1).iso8601) })

      get_overview
      expect(response).to have_http_status(:ok)

      extraction = Kyc::CompletenessCalculator.for(applicant).dimensions.find { |d| d.key == :extraction }
      expect(extraction.numerator).to eq(0)

      readiness = Kyc::Compliance::ReadinessAssessment.for(applicant)
      expect(readiness).not_to be_compliant
      expect(readiness.unmet_results).not_to be_empty
      expect(readiness.confirmation_required_results).to be_empty
    end
  end

  context "with a stale document" do
    it "does not count toward completeness and readiness is not compliant (unmet)" do
      entity
      create_certificate_of_incorporation
      create(:kyc_document, applicant: applicant, corporate_entity: entity, document_type: :utility_bill,
             classification_status: :confirmed, status: :complete,
             validity_dates: { "issued" => validity_dates_for(normalized: (applicant.validity_reference_date - 4.months).iso8601) })

      get_overview
      expect(response).to have_http_status(:ok)

      extraction = Kyc::CompletenessCalculator.for(applicant).dimensions.find { |d| d.key == :extraction }
      expect(extraction.numerator).to eq(0)

      readiness = Kyc::Compliance::ReadinessAssessment.for(applicant)
      expect(readiness).not_to be_compliant
      expect(readiness.unmet_results).not_to be_empty
    end
  end

  context "with a confirmation_required document" do
    it "does not count toward completeness, and blocks readiness distinctly from an outright rejection" do
      entity
      create_certificate_of_incorporation
      create(:kyc_document, applicant: applicant, corporate_entity: entity, document_type: :passport,
             classification_status: :confirmed, status: :complete,
             validity_dates: { "expiry" => validity_dates_for(normalized: nil, confidence: nil) })

      get_overview
      expect(response).to have_http_status(:ok)

      extraction = Kyc::CompletenessCalculator.for(applicant).dimensions.find { |d| d.key == :extraction }
      expect(extraction.numerator).to eq(0)

      readiness = Kyc::Compliance::ReadinessAssessment.for(applicant)
      expect(readiness).not_to be_compliant
      expect(readiness.confirmation_required_results).not_to be_empty
      expect(readiness.confirmation_required_results & readiness.unmet_results).to be_empty

      # MH-200: the overview tab must render this distinctly from an
      # outright rejection — amber "Awaiting Review", not red "Not
      # Compliant" — with the awaiting item actually listed.
      expect(response.body).to include("Awaiting Review")
      expect(response.body).not_to include("Not Compliant")
      expect(response.body).to include("awaiting-confirmation-summary")
      expect(response.body).to include("Passport")
    end
  end

  context "with a document type outside validity rollout" do
    it "keeps pre-MH-198 completeness/readiness behaviour unaffected" do
      entity
      create_certificate_of_incorporation
      create(:kyc_document, applicant: applicant, corporate_entity: entity, document_type: :driving_licence,
             classification_status: :confirmed, status: :complete)

      get_overview
      expect(response).to have_http_status(:ok)

      extraction = Kyc::CompletenessCalculator.for(applicant).dimensions.find { |d| d.key == :extraction }
      expect(extraction.numerator).to eq(1)
      expect(extraction.denominator).to eq(1)

      readiness = Kyc::Compliance::ReadinessAssessment.for(applicant)
      document_validity_result = readiness.results_for(entity)
                                           .find { |r| r.rule_name == Kyc::Compliance::Rules::DocumentValidity.rule_name }
      expect(document_validity_result).to be_not_applicable
      expect(readiness).to be_compliant
    end
  end

  context "when the overview tab is loaded repeatedly (simulating multiple staff page loads)" do
    it "does not create duplicate validity assessments or warnings" do
      entity
      create_certificate_of_incorporation
      create(:kyc_document, applicant: applicant, corporate_entity: entity, document_type: :passport,
             classification_status: :confirmed, status: :complete,
             validity_dates: { "expiry" => validity_dates_for(normalized: (applicant.validity_reference_date + 2.years).iso8601) })

      get_overview
      expect(response).to have_http_status(:ok)

      expect {
        3.times { get_overview }
      }.not_to change(Kyc::DocumentValidityAssessment, :count)
    end
  end
end
