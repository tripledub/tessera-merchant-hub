# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::DocumentValidity::Assessor do
  let_it_be(:actor) { create(:user, :psp_admin) }

  def confirm(document, role, value, reason: nil)
    Kyc::DocumentDateConfirmation.create!(
      kyc_document: document, date_role: role, confirmed_value: value,
      extracted_value: document.validity_dates.dig(role, "normalized"),
      confirmed_by: actor, reason: reason
    )
  end

  def validity_dates_for(normalized:, confidence:)
    { "raw" => normalized, "normalized" => normalized, "confidence" => confidence, "provenance" => "ai_extraction" }
  end

  describe ".call" do
    context "with expires mode (passport)" do
      before do
        Kyc::DocumentValidityPolicy.publish!(
          document_type: "passport", effective_from: Date.new(2025, 1, 1),
          mode: :expires, required_dates: [ "expiry" ], warning_thresholds: [ 90, 30 ]
        )
      end

      it "is valid when the expiry date is outside all warning thresholds" do
        reference_date = Date.new(2026, 1, 1)
        document = create(:kyc_document, document_type: "passport",
                           validity_dates: { "expiry" => validity_dates_for(normalized: "2026-12-01", confidence: 0.95) })

        assessment = described_class.call(document: document, reference_date: reference_date)

        expect(assessment).to be_valid_outcome
        expect(assessment.reason_code).to eq("within_validity_window")
        expect(assessment.dates_used).to eq({ "expiry" => { "date" => "2026-12-01", "source" => "extracted" } })
      end

      it "is expiring_soon and identifies the 90-day threshold crossed" do
        reference_date = Date.new(2026, 1, 1)
        expiry = reference_date + 80
        document = create(:kyc_document, document_type: "passport",
                           validity_dates: { "expiry" => validity_dates_for(normalized: expiry.iso8601, confidence: 0.95) })

        assessment = described_class.call(document: document, reference_date: reference_date)

        expect(assessment).to be_expiring_soon_outcome
        expect(assessment.reason_code).to eq("within_90_day_threshold")
        expect(assessment.reason_details).to eq({ "threshold_days" => 90, "days_remaining" => 80 })
      end

      it "is expiring_soon and identifies the 30-day threshold crossed" do
        reference_date = Date.new(2026, 1, 1)
        expiry = reference_date + 10
        document = create(:kyc_document, document_type: "passport",
                           validity_dates: { "expiry" => validity_dates_for(normalized: expiry.iso8601, confidence: 0.95) })

        assessment = described_class.call(document: document, reference_date: reference_date)

        expect(assessment).to be_expiring_soon_outcome
        expect(assessment.reason_code).to eq("within_30_day_threshold")
        expect(assessment.reason_details).to eq({ "threshold_days" => 30, "days_remaining" => 10 })
      end

      # These two boundary tests isolate the expired/not-expired edge from the
      # warning-threshold logic (covered separately above) by publishing a
      # newer policy version with no warning thresholds configured — at
      # exactly 0 days remaining, a [90, 30] threshold config would otherwise
      # also legitimately classify the exact-expiry-date case as
      # "expiring_soon" (0 <= 30), which is a real, correctly-handled outcome
      # covered by the threshold tests above, not a conflict with this AC.
      it "is valid on the exact printed expiry date" do
        expiry = Date.new(2026, 6, 15)
        Kyc::DocumentValidityPolicy.publish!(document_type: "passport", effective_from: Date.new(2025, 1, 1),
                                              mode: :expires, required_dates: [ "expiry" ], warning_thresholds: [])
        document = create(:kyc_document, document_type: "passport",
                           validity_dates: { "expiry" => validity_dates_for(normalized: expiry.iso8601, confidence: 0.95) })

        assessment = described_class.call(document: document, reference_date: expiry)

        expect(assessment).to be_valid_outcome
      end

      it "is expired the calendar day after the printed expiry date" do
        expiry = Date.new(2026, 6, 15)
        Kyc::DocumentValidityPolicy.publish!(document_type: "passport", effective_from: Date.new(2025, 1, 1),
                                              mode: :expires, required_dates: [ "expiry" ], warning_thresholds: [])
        document = create(:kyc_document, document_type: "passport",
                           validity_dates: { "expiry" => validity_dates_for(normalized: expiry.iso8601, confidence: 0.95) })

        assessment = described_class.call(document: document, reference_date: expiry + 1)

        expect(assessment).to be_expired_outcome
        expect(assessment.reason_code).to eq("past_printed_expiry")
      end
    end

    context "with freshness mode (utility_bill)" do
      before do
        Kyc::DocumentValidityPolicy.publish!(
          document_type: "utility_bill", effective_from: Date.new(2020, 1, 1),
          mode: :freshness, required_dates: [ "issued" ], warning_thresholds: [], max_age_months: 3
        )
      end

      it "accepts a bill dated exactly three calendar months before the reference date" do
        reference_date = Date.new(2026, 6, 30)
        issued = reference_date - 3.months
        document = create(:kyc_document, document_type: "utility_bill",
                           validity_dates: { "issued" => validity_dates_for(normalized: issued.iso8601, confidence: 0.95) })

        assessment = described_class.call(document: document, reference_date: reference_date)

        expect(assessment).to be_valid_outcome
      end

      it "is stale for a bill dated one day earlier than the cutoff" do
        reference_date = Date.new(2026, 6, 30)
        issued = reference_date - 3.months - 1
        document = create(:kyc_document, document_type: "utility_bill",
                           validity_dates: { "issued" => validity_dates_for(normalized: issued.iso8601, confidence: 0.95) })

        assessment = described_class.call(document: document, reference_date: reference_date)

        expect(assessment).to be_stale_outcome
        expect(assessment.reason_code).to eq("older_than_max_age")
      end

      it "handles a month-end/leap-year cutoff correctly (Feb 29 reference date)" do
        # Leap year: Feb 29 2024 - 3 months = Nov 29 2023 (no clamping needed).
        reference_date = Date.new(2024, 2, 29)
        cutoff = reference_date - 3.months
        document = create(:kyc_document, document_type: "utility_bill",
                           validity_dates: { "issued" => validity_dates_for(normalized: cutoff.iso8601, confidence: 0.95) })

        assessment = described_class.call(document: document, reference_date: reference_date)

        expect(assessment).to be_valid_outcome

        stale_document = create(:kyc_document, document_type: "utility_bill",
                                 validity_dates: { "issued" => validity_dates_for(normalized: (cutoff - 1).iso8601, confidence: 0.95) })
        stale_assessment = described_class.call(document: stale_document, reference_date: reference_date)

        expect(stale_assessment).to be_stale_outcome
      end

      it "handles an end-of-month reference date where the cutoff month is shorter (Nov 30 -> Aug 30)" do
        reference_date = Date.new(2026, 11, 30)
        cutoff = reference_date - 3.months
        expect(cutoff).to eq(Date.new(2026, 8, 30))

        document = create(:kyc_document, document_type: "utility_bill",
                           validity_dates: { "issued" => validity_dates_for(normalized: cutoff.iso8601, confidence: 0.95) })

        assessment = described_class.call(document: document, reference_date: reference_date)

        expect(assessment).to be_valid_outcome
      end
    end

    context "when a required date lacks an authoritative value" do
      before do
        Kyc::DocumentValidityPolicy.publish!(
          document_type: "passport", effective_from: Date.new(2025, 1, 1),
          mode: :expires, required_dates: [ "expiry" ], warning_thresholds: [ 90, 30 ]
        )
      end

      it "requires confirmation when the required date has no confirmation and low/no confidence extraction" do
        document = create(:kyc_document, document_type: "passport",
                           validity_dates: { "expiry" => validity_dates_for(normalized: nil, confidence: nil) })

        assessment = described_class.call(document: document, reference_date: Date.new(2026, 1, 1))

        expect(assessment).to be_confirmation_required_outcome
      end

      it "uses the confirmed value and ignores extraction confidence entirely once confirmed" do
        document = create(:kyc_document, document_type: "passport",
                           validity_dates: { "expiry" => validity_dates_for(normalized: nil, confidence: nil) })
        confirm(document, "expiry", Date.new(2026, 12, 1))

        assessment = described_class.call(document: document, reference_date: Date.new(2026, 1, 1))

        expect(assessment).to be_valid_outcome
        expect(assessment.dates_used).to eq({ "expiry" => { "date" => "2026-12-01", "source" => "confirmed" } })
      end
    end

    context "when a document is reassessed" do
      before do
        Kyc::DocumentValidityPolicy.publish!(
          document_type: "passport", effective_from: Date.new(2025, 1, 1),
          mode: :expires, required_dates: [ "expiry" ], warning_thresholds: [ 90, 30 ]
        )
      end

      it "creates a new historical record each time rather than overwriting the previous one" do
        document = create(:kyc_document, document_type: "passport",
                           validity_dates: { "expiry" => validity_dates_for(normalized: "2026-12-01", confidence: 0.95) })

        expect {
          described_class.call(document: document, reference_date: Date.new(2026, 1, 1))
        }.to change(Kyc::DocumentValidityAssessment, :count).by(1)

        expect {
          described_class.call(document: document, reference_date: Date.new(2026, 1, 2))
        }.to change(Kyc::DocumentValidityAssessment, :count).by(1)

        expect(Kyc::DocumentValidityAssessment.where(kyc_document: document).count).to eq(2)
        latest = described_class.call(document: document, reference_date: Date.new(2026, 1, 3))
        expect(Kyc::DocumentValidityAssessment.current_for(document)).to eq(latest)
      end
    end

    context "without a resolvable policy" do
      it "returns nil and creates no assessment for a document type without an enabled policy" do
        document = create(:kyc_document, document_type: "driving_licence")

        expect {
          result = described_class.call(document: document, reference_date: Date.current)
          expect(result).to be_nil
        }.not_to change(Kyc::DocumentValidityAssessment, :count)
      end

      it "returns nil and creates no assessment when the only policy is disabled" do
        Kyc::DocumentValidityPolicy.publish!(
          document_type: "passport", effective_from: Date.new(2025, 1, 1),
          mode: :expires, required_dates: [ "expiry" ], enabled: false
        )
        document = create(:kyc_document, document_type: "passport")

        expect {
          result = described_class.call(document: document, reference_date: Date.current)
          expect(result).to be_nil
        }.not_to change(Kyc::DocumentValidityAssessment, :count)
      end
    end

    context "with a DST transition (Europe/London reference date resolution)" do
      it "resolves Date.current correctly across the UK spring-forward DST boundary" do
        Kyc::DocumentValidityPolicy.publish!(
          document_type: "passport", effective_from: Date.new(2025, 1, 1),
          mode: :expires, required_dates: [ "expiry" ], warning_thresholds: [ 90, 30 ]
        )

        Time.use_zone("Europe/London") do
          # 2026-03-29 01:30 UTC is 2026-03-29 02:30 BST after the UK clocks
          # spring forward at 01:00 UTC. Date.current must still resolve to
          # 2026-03-29 in the local (London) zone, not drift a day either way.
          travel_to(Time.zone.local(2026, 3, 29, 2, 30)) do
            expect(Time.zone.name).to eq("Europe/London")
            expect(Date.current).to eq(Date.new(2026, 3, 29))

            document = create(:kyc_document, document_type: "passport",
                               validity_dates: { "expiry" => validity_dates_for(normalized: "2028-01-01", confidence: 0.95) })

            assessment = described_class.call(document: document, reference_date: Date.current)

            expect(assessment).to be_valid_outcome
            expect(assessment.reference_date).to eq(Date.new(2026, 3, 29))
          end
        end
      end
    end

    it "never uses Time.now or Date.today anywhere in the new service/model code" do
      files = Dir[Rails.root.join("app/services/kyc/document_validity/assessor.rb"),
                  Rails.root.join("app/models/kyc/document_validity_assessment.rb")]
      offenders = files.flat_map do |file|
        File.readlines(file).each_with_index.select { |line, _| line.match?(/\bTime\.now\b|\bDate\.today\b/) }
                            .map { |line, idx| "#{file}:#{idx + 1}: #{line.strip}" }
      end

      expect(offenders).to be_empty
    end
  end
end
