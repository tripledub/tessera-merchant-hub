# frozen_string_literal: true

module Statements
  class Importer
    CURRENCY_FORMAT = /\A[A-Z]{3}\z/

    def initialize(processing_statement, mapping)
      @processing_statement = processing_statement
      @mapping = mapping.stringify_keys
    end

    def call
      return if superseded?

      missing = ProcessingStatement::REQUIRED_FIELDS.map(&:to_s) - mapping.keys
      return fail!("Missing required field mapping: #{missing.join(', ')}") if missing.any?

      rows = build_rows
      result = MetricsCalculator.new(rows).call

      processing_statement.update!(
        status: :processed,
        column_mapping: mapping,
        row_count: rows.size,
        metrics: result,
        error_message: nil
      )
    rescue ArgumentError, TypeError, KeyError => e
      fail!("Could not parse statement data: #{e.message}")
    rescue SpreadsheetReader::RowLimitExceeded => e
      fail!(e.message)
    rescue StandardError => e
      # Defense in depth: whatever the underlying spreadsheet library or a
      # malformed file throws that we haven't anticipated must still land
      # the statement in :error, not leave it stuck in :mapped forever —
      # this is exactly the class of bug fixed in MH-232 for KYC documents.
      fail!("Import failed: #{e.message}")
    end

    private

    attr_reader :processing_statement, :mapping

    # A later mapping submission for the same statement can enqueue a
    # second job before this one runs; without this guard, jobs completing
    # out of order could let a stale result overwrite a newer one.
    def superseded?
      processing_statement.reload.column_mapping.stringify_keys != mapping
    end

    def build_rows
      reader = SpreadsheetReader.new(processing_statement)
      reader.row_count!
      reader.each_row_hash.map do |raw_row|
        {
          date: parse_date(raw_row.fetch(mapping.fetch("date")).to_s),
          amount: BigDecimal(raw_row.fetch(mapping.fetch("amount")).to_s),
          currency: parse_currency(raw_row.fetch(mapping.fetch("currency")).to_s),
          outcome: raw_row.fetch(mapping.fetch("outcome")).to_s
        }
      end
    end

    # Date.parse alone guesses ambiguously-ordered dates (04/05/2026 could
    # be 4 May or 5 April) inconsistently. ISO 8601 (YYYY-MM-DD) is
    # unambiguous, so prefer that reading when the value looks like one;
    # any other format still falls back to Date.parse's best-effort guess
    # (residual ambiguity for non-ISO formats is a known v1 limitation).
    def parse_date(value)
      return Date.iso8601(value) if value.match?(/\A\d{4}-\d{2}-\d{2}/)

      Date.parse(value)
    end

    # Strict ISO-4217-shaped (3 letters) after normalizing case/whitespace.
    # This also closes off CSV-formula-injection via the currency column
    # (see Statements::ReportExporter) — a code matching this format can't
    # contain '=', '+', '-', '@', or any other formula-trigger character.
    def parse_currency(value)
      normalized = value.strip.upcase
      raise ArgumentError, "Invalid currency code: #{value.inspect}" unless normalized.match?(CURRENCY_FORMAT)

      normalized
    end

    def fail!(message)
      processing_statement.update!(status: :error, error_message: message)
    end
  end
end
