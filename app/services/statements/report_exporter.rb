# frozen_string_literal: true

module Statements
  class ReportExporter
    COLUMNS = %w[
      period total_volume approved_volume declined_volume
      transaction_count chargeback_count chargeback_percentage
      refund_count refund_percentage currencies
    ].freeze

    def initialize(processing_statement)
      @metrics = processing_statement.metrics
    end

    def to_csv
      CSV.generate(headers: true) do |csv|
        csv << COLUMNS

        by_month.each { |period, row| csv << row_values(period, row) }
        csv << row_values("overall", overall)
      end
    end

    private

    attr_reader :metrics

    def by_month
      metrics.fetch("by_month", {})
    end

    def overall
      metrics.fetch("overall", {})
    end

    FORMULA_TRIGGERS = [ "=", "+", "-", "@", "\t", "\r" ].freeze

    def row_values(period, row)
      [
        period, volume(row["total_volume"]), volume(row["approved_volume"]), volume(row["declined_volume"]),
        row["transaction_count"], row["chargeback_count"], row["chargeback_percentage"],
        row["refund_count"], row["refund_percentage"], csv_safe(Array(row["currencies"]).join("; "))
      ]
    end

    # Amounts are per-currency (e.g. {"GBP" => "175.0", "EUR" => "30.0"}) and
    # are never summed across currencies — rendered as one "CUR 0.00" figure
    # per currency present. Importer's strict currency-format validation
    # already rules out formula-injection characters here, but csv_safe is
    # applied too as defense in depth for any legacy/unvalidated data.
    def volume(volume_by_currency)
      csv_safe(Hash(volume_by_currency).map { |currency, amount| "#{currency} #{format_amount(amount)}" }.join("; "))
    end

    # Stays in BigDecimal arithmetic throughout — no Float conversion —
    # since these are financial totals, not merely display-only figures
    # with float-safe magnitude.
    def format_amount(value)
      whole, fraction = BigDecimal(value.to_s).round(2).to_s("F").split(".")
      "#{whole}.#{(fraction || '').ljust(2, '0')[0, 2]}"
    end

    # Neutralizes spreadsheet-formula injection: a cell value starting with
    # =, +, -, @, tab, or CR can execute as a formula when the CSV is
    # opened in Excel/Sheets. Prefixing with a single quote forces it to
    # render as literal text instead.
    def csv_safe(value)
      value = value.to_s
      FORMULA_TRIGGERS.any? { |trigger| value.start_with?(trigger) } ? "'#{value}" : value
    end
  end
end
