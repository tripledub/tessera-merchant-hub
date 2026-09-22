# frozen_string_literal: true

require "rails_helper"

# MH-320: proves the exact 3-month freshness boundary
# (config/kyc/policies/base.yml's base.utility_bill_freshness,
# max_age_months: 3) through the real confirm-date endpoint and
# Kyc::DocumentValidity::Assessor together, not just Assessor's own unit
# logic (already exhaustively covered in isolation by
# spec/services/kyc/document_validity/assessor_spec.rb).
#
# Utility bills never auto-resolve their issued date: Kyc::DocumentExtractorService
# supplies no per-field confidence for them (no MRZ-equivalent signal exists,
# see Kyc::DocumentValidity::DateExtractor), so DateExtractor#needs_confirmation?
# is always true and the date requires staff confirmation before Assessor can
# treat it as authoritative. This spec reflects that: it drives the same
# POST a reviewer's "Confirm date" button uses, at each side of the
# boundary, using extracted_data/validity_dates matching the real,
# Claude-verified ground truth for specimen_utilitybill_alex_testperson.pdf
# (spec/fixtures/files).
RSpec.describe "Utility bill freshness boundary", type: :request do
  let_it_be(:psp_admin) { create(:user, :psp_admin) }
  let_it_be(:applicant) { create(:applicant) }

  # Arbitrary, fixed, wall-clock-independent — the fixture's printed issue
  # date. The boundary itself is exercised via the *confirmed* value below,
  # not this raw extracted one.
  let(:extracted_issue_date) { "2020-01-15" }

  let!(:document) do
    create(:kyc_document,
      applicant: applicant,
      document_type: :utility_bill,
      classification_status: :confirmed,
      extracted_data: {
        "full_name" => "Alex Testperson",
        "account_holder_address_line1" => "12 High Street",
        "account_holder_city" => "London",
        "account_holder_postcode" => "SW1A 1AA",
        "account_holder_country" => "United Kingdom",
        "provider" => "Utopia Power & Light",
        "issue_date" => extracted_issue_date
      },
      validity_dates: {
        "issued" => { "raw" => extracted_issue_date, "normalized" => extracted_issue_date,
                       "confidence" => nil, "provenance" => "ai_extraction" }
      },
      validity_confirmation_required: true)
  end

  before do
    Kyc::DocumentValidityPolicy.publish!(
      document_type: "utility_bill", effective_from: Date.new(2020, 1, 1),
      mode: :freshness, required_dates: [ "issued" ], warning_thresholds: [], max_age_months: 3
    )
    sign_in psp_admin
  end

  def confirm_issued_date(confirmed_value)
    post kyc_document_date_confirmations_path,
         params: { kyc_document_id: document.id, date_role: "issued", confirmed_value: confirmed_value,
                   reason: "Reviewer confirmed the printed issue date" }
  end

  it "is valid when confirmed as issued exactly 3 months before the reference date", qase_id: 16 do
    reference_date = Date.new(2026, 9, 22)
    confirmed = reference_date - 3.months

    confirm_issued_date(confirmed.iso8601)
    expect(response).to have_http_status(:ok).or have_http_status(:redirect)

    assessment = Kyc::DocumentValidity::Assessor.call(document: document.reload, reference_date: reference_date)

    expect(assessment).to be_valid_outcome
    expect(assessment.dates_used.dig("issued", "source")).to eq("confirmed")
  end

  it "is stale when confirmed as issued 3 months and one day before the reference date", qase_id: 16 do
    reference_date = Date.new(2026, 9, 22)
    confirmed = reference_date - 3.months - 1.day

    confirm_issued_date(confirmed.iso8601)
    expect(response).to have_http_status(:ok).or have_http_status(:redirect)

    assessment = Kyc::DocumentValidity::Assessor.call(document: document.reload, reference_date: reference_date)

    expect(assessment).to be_stale_outcome
    expect(assessment.reason_code).to eq("older_than_max_age")
  end

  it "requires review before any confirmation — the extracted date alone is never authoritative" do
    reference_date = Date.new(2026, 9, 22)

    assessment = Kyc::DocumentValidity::Assessor.call(document: document, reference_date: reference_date)

    expect(assessment).to be_confirmation_required_outcome
    expect(assessment.reason_code).to eq("missing_required_date")
  end
end
