# frozen_string_literal: true

module Statements
  # MH-325: pre-fills the Processing Statement mapping screen with a
  # best-guess column for each required field, so a reviewer only needs to
  # confirm (or correct) rather than map every field from scratch on every
  # statement. Deliberately an exact/case-insensitive synonym-list match,
  # not fuzzy string similarity — predictable and auditable, and safe to
  # extend as real header text turns up. Never guesses when nothing in the
  # synonym list matches; a wrong guess into a required field (especially
  # currency) is worse than leaving it for manual mapping.
  class ColumnMappingSuggester
    SYNONYMS = {
      "date" => [ "date", "transaction date", "txn date", "value date", "posting date" ],
      "amount" => [ "amount", "value", "txn amount", "transaction amount", "amount (gbp)" ],
      "currency" => [ "currency", "ccy", "curr" ],
      "outcome" => [ "outcome", "status", "result", "transaction status" ]
    }.freeze

    def self.call(headers:)
      new(headers).call
    end

    def initialize(headers)
      @headers = headers
    end

    def call
      SYNONYMS.each_with_object({}) do |(field, synonyms), suggestions|
        match = @headers.find { |header| synonyms.include?(header.to_s.strip.downcase) }
        suggestions[field] = match if match
      end
    end
  end
end
