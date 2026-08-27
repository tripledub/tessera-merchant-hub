# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProcessingStatementPresenter, type: :presenter do
  let(:template) { ApplicationController.new.view_context }
  let(:presenter) { described_class.new(processing_statement, template) }

  describe "state predicates" do
    it "reports queued? for a mapped (queued) statement" do
      presenter = described_class.new(build(:processing_statement, status: :mapped), template)
      expect(presenter.queued?).to be true
      expect(presenter.failed?).to be false
      expect(presenter.ready?).to be false
    end

    it "reports failed? for an errored statement" do
      presenter = described_class.new(build(:processing_statement, status: :error), template)
      expect(presenter.failed?).to be true
    end

    it "reports ready? for a processed statement" do
      presenter = described_class.new(build(:processing_statement, status: :processed), template)
      expect(presenter.ready?).to be true
    end
  end

  describe "#overall and #monthly_breakdown" do
    let(:processing_statement) do
      build(:processing_statement, status: :processed, metrics: {
        "overall" => {
          "total_volume" => { "GBP" => "175.0", "EUR" => "30.0" }, "approved_volume" => { "GBP" => "175.0" },
          "declined_volume" => {}, "chargeback_count" => 1, "chargeback_percentage" => 50.0,
          "refund_count" => 0, "refund_percentage" => 0.0, "currencies" => [ "GBP", "EUR" ]
        },
        "by_month" => {
          "2026-04" => {
            "total_volume" => { "GBP" => "175.0" }, "approved_volume" => { "GBP" => "175.0" },
            "declined_volume" => {}, "chargeback_count" => 1, "chargeback_percentage" => 100.0,
            "refund_count" => 0, "refund_percentage" => 0.0, "currencies" => [ "GBP" ]
          }
        }
      })
    end

    it "formats overall volume to 2dp per currency, never blended" do
      expect(presenter.overall.total_volume).to eq("GBP 175.00, EUR 30.00")
      expect(presenter.overall.approved_volume).to eq("GBP 175.00")
    end

    it "shows a placeholder when a period has no data for a figure" do
      expect(presenter.overall.declined_volume).to eq(I18n.t("processing_statements.show.no_data"))
    end

    it "exposes one entry per month, labeled and formatted the same way" do
      breakdown = presenter.monthly_breakdown
      expect(breakdown.size).to eq(1)
      expect(breakdown.first.label).to eq("2026-04")
      expect(breakdown.first.total_volume).to eq("GBP 175.00")
    end
  end
end
