# frozen_string_literal: true

module Statements
  class Importer
    CURRENCY_FORMAT = /\A[A-Z]{3}\z/
    SUMMARY_FOOTER = "SUMMARY"

    class ParseError < StandardError
      def initialize(row_number:, logical_field:, mapped_column:, value:, reason:)
        message = "Row #{row_number}, field #{logical_field.inspect}, column #{mapped_column.inspect}, " \
          "value #{diagnostic_value(value)}: #{reason}"
        super(message)
      end

      private

      def diagnostic_value(value)
        scalar = value.to_s
        scalar = "#{scalar[0, 200]}…" if scalar.length > 200
        scalar.inspect
      end
    end

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
    rescue ParseError => e
      fail!(e.message)
    rescue ArgumentError, TypeError, KeyError => e
      fail!("Could not parse statement data: #{e.message}")
    rescue SpreadsheetReader::RowLimitExceeded => e
      fail!(e.message)
    rescue StandardError
      # Defense in depth: whatever the underlying spreadsheet library or a
      # malformed file throws that we haven't anticipated must still land
      # the statement in :error, not leave it stuck in :mapped forever —
      # this is exactly the class of bug fixed in MH-232 for KYC documents.
      fail!("Import failed while processing statement data.")
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
      rows = []
      reader.each_row_hash.with_index(2) do |raw_row, row_number|
        break if summary_footer?(raw_row)
        next if blank_row?(raw_row)

        rows << {
          date: parse_field(raw_row, row_number, "date") { |value| parse_date(value) },
          amount: parse_field(raw_row, row_number, "amount") { |value| parse_amount(value) },
          currency: parse_field(raw_row, row_number, "currency") { |value| parse_currency(value) },
          outcome: parse_field(raw_row, row_number, "outcome", &:itself)
        }
      end
      rows
    end

    def summary_footer?(raw_row)
      values = raw_row.values.map { |value| value.to_s.strip }
      first_populated_index = values.index(&:present?)
      return false unless first_populated_index

      values[first_populated_index].casecmp?(SUMMARY_FOOTER) && values.drop(first_populated_index + 1).all?(&:blank?)
    end

    def blank_row?(raw_row)
      raw_row.values.all? { |value| value.to_s.strip.blank? }
    end

    def parse_field(raw_row, row_number, logical_field)
      mapped_column = mapping.fetch(logical_field)
      value = raw_row.fetch(mapped_column)
      yield value.to_s
    rescue ArgumentError, TypeError => e
      raise ParseError.new(
        row_number: row_number,
        logical_field: logical_field,
        mapped_column: mapped_column,
        value: value,
        reason: e.message
      )
    end

    # Date.parse alone guesses ambiguously-ordered dates (04/05/2026 could
    # be 4 May or 5 April) inconsistently. ISO 8601 (YYYY-MM-DD) is
    # unambiguous, so prefer that reading when the value looks like one;
    # any other format still falls back to Date.parse's best-effort guess
    # (residual ambiguity for non-ISO formats is a known v1 limitation).
    def parse_date(value)
      return Date.iso8601(value) if value.match?(/\A\d{4}-\d{2}-\d{2}/)

      Date.parse(value)
    rescue ArgumentError, TypeError
      raise ArgumentError, "invalid date"
    end

    def parse_amount(value)
      BigDecimal(value)
    rescue ArgumentError, TypeError
      raise ArgumentError, "invalid amount"
    end

    # Strict ISO-4217-shaped (3 letters) after normalizing case/whitespace.
    # This also closes off CSV-formula-injection via the currency column
    # (see Statements::ReportExporter) — a code matching this format can't
    # contain '=', '+', '-', '@', or any other formula-trigger character.
    def parse_currency(value)
      normalized = value.strip.upcase
      raise ArgumentError, "invalid currency code" unless normalized.match?(CURRENCY_FORMAT)

      normalized
    end

    def fail!(message)
      processing_statement.update!(status: :error, error_message: message)
    end
  end
end
