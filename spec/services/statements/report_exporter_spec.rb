# frozen_string_literal: true

require "rails_helper"

RSpec.describe Statements::ReportExporter do
  let(:statement) do
    create(:processing_statement, status: :processed, metrics: {
      "overall" => {
        "total_volume" => { "GBP" => "175.0", "EUR" => "30.0" }, "approved_volume" => { "GBP" => "175.0" },
        "declined_volume" => { "EUR" => "30.0" },
        "transaction_count" => 2, "chargeback_count" => 0, "chargeback_percentage" => 0.0,
        "refund_count" => 0, "refund_percentage" => 0.0, "currencies" => [ "GBP", "EUR" ]
      },
      "by_month" => {
        "2026-04" => {
          "total_volume" => { "GBP" => "175.0" }, "approved_volume" => { "GBP" => "175.0" }, "declined_volume" => {},
          "transaction_count" => 1, "chargeback_count" => 0, "chargeback_percentage" => 0.0,
          "refund_count" => 0, "refund_percentage" => 0.0, "currencies" => [ "GBP" ]
        }
      }
    })
  end

  describe "#to_csv" do
    it "includes a header row, one row per month, and an overall row" do
      csv = CSV.parse(described_class.new(statement).to_csv, headers: true)

      expect(csv.headers).to include("period", "total_volume", "approved_volume", "declined_volume",
        "chargeback_count", "chargeback_percentage", "refund_count", "refund_percentage", "currencies")
      expect(csv.map { |row| row["period"] }).to contain_exactly("2026-04", "overall")
      expect(csv.find { |row| row["period"] == "2026-04" }["total_volume"]).to eq("GBP 175.00")
    end

    it "never sums amounts across currencies — each currency gets its own figure" do
      csv = CSV.parse(described_class.new(statement).to_csv, headers: true)

      expect(csv.find { |row| row["period"] == "overall" }["total_volume"]).to eq("GBP 175.00; EUR 30.00")
    end

    it "neutralizes a formula-injection-style currency value instead of writing it literally" do
      statement.update!(metrics: {
        "overall" => { "currencies" => [ "=cmd|'/c calc'!A1" ] },
        "by_month" => {}
      })

      csv_text = described_class.new(statement).to_csv

      expect(csv_text).not_to include("\n=cmd")
      expect(csv_text).to include("'=cmd|'/c calc'!A1")
    end
  end
end
