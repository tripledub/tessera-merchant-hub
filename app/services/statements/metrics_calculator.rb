# frozen_string_literal: true

module Statements
  class MetricsCalculator
    # Exact-match lookup on a normalized (downcased, punctuation-stripped)
    # outcome value — not substring/regex matching. Substring matching
    # previously misclassified values like "unsuccessful" as approved
    # (it contains "success") and could match more than one category for
    # the same row; a lookup table is inherently mutually exclusive and
    # only matches known, literal outcome values.
    APPROVED_VALUES   = %w[success successful approved approve authorised authorized captured completed paid].freeze
    DECLINED_VALUES   = %w[declined decline failed fail failure rejected reject].freeze
    CHARGEBACK_VALUES = %w[chargeback chargebacks chargedback].freeze
    REFUND_VALUES     = %w[refund refunded refunds].freeze

    def initialize(rows)
      @rows = rows
    end

    def call
      grouped = rows.group_by { |row| row[:date].strftime("%Y-%m") }

      {
        overall: metrics_for(rows),
        by_month: grouped.sort.to_h { |month, month_rows| [ month, metrics_for(month_rows) ] }
      }
    end

    private

    attr_reader :rows

    def metrics_for(rows)
      classified = rows.group_by { |r| classify(r[:outcome]) }
      total_count = rows.size
      chargeback_count = classified.fetch(:chargeback, []).size
      refund_count = classified.fetch(:refund, []).size

      {
        total_volume: sum_by_currency(rows),
        approved_volume: sum_by_currency(classified.fetch(:approved, [])),
        declined_volume: sum_by_currency(classified.fetch(:declined, [])),
        transaction_count: total_count,
        chargeback_count: chargeback_count,
        chargeback_percentage: percentage_of(chargeback_count, total_count),
        refund_count: refund_count,
        refund_percentage: percentage_of(refund_count, total_count),
        currencies: rows.map { |r| r[:currency] }.uniq
      }
    end

    def classify(outcome)
      normalized = outcome.to_s.strip.downcase.gsub(/[^a-z]/, "")
      return :chargeback if CHARGEBACK_VALUES.include?(normalized)
      return :refund if REFUND_VALUES.include?(normalized)
      return :approved if APPROVED_VALUES.include?(normalized)
      return :declined if DECLINED_VALUES.include?(normalized)

      :other
    end

    # Amounts are never summed across currencies — a total that blends e.g.
    # GBP and EUR would be a meaningless number, not a real figure.
    def sum_by_currency(rows)
      rows.group_by { |r| r[:currency] }
        .transform_values { |group| group.sum(BigDecimal("0")) { |r| r[:amount] } }
    end

    def percentage_of(count, total)
      return 0.0 if total.zero?

      (count.to_f / total * 100).round(2)
    end
  end
end
