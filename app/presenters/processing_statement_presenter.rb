# frozen_string_literal: true

class ProcessingStatementPresenter < BasePresenter
  presents :processing_statement

  PeriodMetrics = Data.define(
    :label, :total_volume, :approved_volume, :declined_volume,
    :chargeback_count, :chargeback_percentage, :refund_count, :refund_percentage, :currencies
  )

  def queued?
    processing_statement.mapped?
  end

  def failed?
    processing_statement.error?
  end

  def ready?
    processing_statement.processed?
  end

  def overall
    period_metrics("overall", metrics.fetch("overall", {}))
  end

  def monthly_breakdown
    metrics.fetch("by_month", {}).map { |month, row| period_metrics(month, row) }
  end

  private

  def metrics
    processing_statement.metrics
  end

  def period_metrics(label, row)
    PeriodMetrics.new(
      label: label,
      total_volume: format_volume(row["total_volume"]),
      approved_volume: format_volume(row["approved_volume"]),
      declined_volume: format_volume(row["declined_volume"]),
      chargeback_count: row["chargeback_count"],
      chargeback_percentage: row["chargeback_percentage"],
      refund_count: row["refund_count"],
      refund_percentage: row["refund_percentage"],
      currencies: Array(row["currencies"]).join(", ")
    )
  end

  # Amounts are never summed across currencies — a blended GBP+EUR total
  # would be a meaningless number — so each currency present gets its own
  # 2dp figure. Converts through BigDecimal, not Float, since these are
  # financial totals.
  def format_volume(volume_by_currency)
    return I18n.t("processing_statements.show.no_data") if volume_by_currency.blank?

    volume_by_currency.map { |currency, amount|
      number_to_currency(BigDecimal(amount.to_s), unit: "#{currency} ", precision: 2)
    }.join(", ")
  end
end
