# frozen_string_literal: true

require "rails_helper"

RSpec.describe Statements::MetricsCalculator do
  def row(date:, amount:, currency: "GBP", outcome: "approved")
    { date: Date.parse(date), amount: BigDecimal(amount.to_s), currency: currency, outcome: outcome }
  end

  describe "#call" do
    it "sums total volume per currency, never blending amounts across currencies" do
      rows = [
        row(date: "2026-04-01", amount: 100, currency: "GBP", outcome: "approved"),
        row(date: "2026-04-15", amount: 50, currency: "GBP", outcome: "declined"),
        row(date: "2026-04-20", amount: 30, currency: "EUR", outcome: "approved")
      ]

      result = described_class.new(rows).call

      expect(result[:overall][:total_volume]).to eq({ "GBP" => BigDecimal("150"), "EUR" => BigDecimal("30") })
    end

    it "splits approved and declined volume per currency" do
      rows = [
        row(date: "2026-04-01", amount: 100, currency: "GBP", outcome: "success"),
        row(date: "2026-04-02", amount: 30, currency: "GBP", outcome: "declined"),
        row(date: "2026-04-03", amount: 20, currency: "EUR", outcome: "failed")
      ]

      result = described_class.new(rows).call

      expect(result[:overall][:approved_volume]).to eq({ "GBP" => BigDecimal("100") })
      expect(result[:overall][:declined_volume]).to eq({ "GBP" => BigDecimal("30"), "EUR" => BigDecimal("20") })
    end

    it "counts chargebacks and refunds and computes their percentage of total transaction count" do
      rows = [
        row(date: "2026-04-01", amount: 10, outcome: "approved"),
        row(date: "2026-04-02", amount: 10, outcome: "approved"),
        row(date: "2026-04-03", amount: 10, outcome: "chargeback"),
        row(date: "2026-04-04", amount: 10, outcome: "refunded")
      ]

      result = described_class.new(rows).call

      expect(result[:overall][:chargeback_count]).to eq(1)
      expect(result[:overall][:refund_count]).to eq(1)
      expect(result[:overall][:transaction_count]).to eq(4)
      expect(result[:overall][:chargeback_percentage]).to eq(25.0)
      expect(result[:overall][:refund_percentage]).to eq(25.0)
    end

    it "reports the distinct currencies used" do
      rows = [
        row(date: "2026-04-01", amount: 10, currency: "GBP"),
        row(date: "2026-04-02", amount: 10, currency: "EUR"),
        row(date: "2026-04-03", amount: 10, currency: "GBP")
      ]

      result = described_class.new(rows).call

      expect(result[:overall][:currencies]).to contain_exactly("GBP", "EUR")
    end

    it "breaks totals down by calendar month, per currency" do
      rows = [
        row(date: "2026-04-28", amount: 100, currency: "GBP", outcome: "approved"),
        row(date: "2026-05-02", amount: 50, currency: "GBP", outcome: "approved"),
        row(date: "2026-05-10", amount: 25, currency: "EUR", outcome: "declined")
      ]

      result = described_class.new(rows).call

      expect(result[:by_month].keys).to eq(%w[2026-04 2026-05])
      expect(result[:by_month]["2026-04"][:total_volume]).to eq({ "GBP" => BigDecimal("100") })
      expect(result[:by_month]["2026-05"][:total_volume]).to eq({ "GBP" => BigDecimal("50"), "EUR" => BigDecimal("25") })
      expect(result[:by_month]["2026-05"][:approved_volume]).to eq({ "GBP" => BigDecimal("50") })
      expect(result[:by_month]["2026-05"][:declined_volume]).to eq({ "EUR" => BigDecimal("25") })
    end

    it "classifies outcomes case-insensitively against known values, treating anything else as other" do
      rows = [
        row(date: "2026-04-01", amount: 10, outcome: "SUCCESS"),
        row(date: "2026-04-02", amount: 10, outcome: "Declined"),
        row(date: "2026-04-03", amount: 10, outcome: "pending")
      ]

      result = described_class.new(rows).call

      expect(result[:overall][:approved_volume]).to eq({ "GBP" => BigDecimal("10") })
      expect(result[:overall][:declined_volume]).to eq({ "GBP" => BigDecimal("10") })
      expect(result[:overall][:transaction_count]).to eq(3)
    end

    it "does not misclassify 'unsuccessful' as approved just because it contains 'success'" do
      rows = [ row(date: "2026-04-01", amount: 10, outcome: "unsuccessful") ]

      result = described_class.new(rows).call

      expect(result[:overall][:approved_volume]).to eq({})
      expect(result[:overall][:declined_volume]).to eq({})
    end

    it "classifies each row into exactly one category, never counting it toward more than one" do
      rows = [ row(date: "2026-04-01", amount: 10, outcome: "chargeback") ]

      result = described_class.new(rows).call

      expect(result[:overall][:chargeback_count]).to eq(1)
      expect(result[:overall][:approved_volume]).to eq({})
      expect(result[:overall][:declined_volume]).to eq({})
    end

    it "handles an empty row set without dividing by zero" do
      result = described_class.new([]).call

      expect(result[:overall][:transaction_count]).to eq(0)
      expect(result[:overall][:chargeback_percentage]).to eq(0.0)
      expect(result[:overall][:total_volume]).to eq({})
      expect(result[:by_month]).to eq({})
    end
  end
end
