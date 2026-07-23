# frozen_string_literal: true

module Transcripts
  class IndexQuery
    def initialize(scope, filters)
      @scope = scope
      @filters = filters
    end

    def call
      result = scope
        .includes(:applicant)
        .left_joins(:onboarding_messages)
        .select(
          "onboarding_sessions.*",
          "COUNT(onboarding_messages.id) AS messages_count",
          "GREATEST(onboarding_sessions.updated_at, " \
            "COALESCE(MAX(onboarding_messages.created_at), onboarding_sessions.updated_at)) AS last_activity_at"
        )
        .group("onboarding_sessions.id")

      result = result.where(applicant_id: filters[:applicant_id]) if valid_applicant_id?
      result = result.where(status: filters[:status]) if valid_status?
      result = result.where(current_stage: filters[:current_stage]) if valid_stage?
      result = result.where("onboarding_sessions.created_at >= ?", date_from.beginning_of_day) if date_from
      result = result.where("onboarding_sessions.created_at <= ?", date_to.end_of_day) if date_to
      result.order(Arel.sql(
        "GREATEST(onboarding_sessions.updated_at, " \
          "COALESCE(MAX(onboarding_messages.created_at), onboarding_sessions.updated_at)) DESC"
      ))
    end

    private

    attr_reader :scope, :filters

    def valid_status?
      OnboardingSession.statuses.key?(filters[:status])
    end

    def valid_applicant_id?
      filters[:applicant_id].present? && filters[:applicant_id].match?(/\A[0-9a-f-]{36}\z/i)
    end

    def valid_stage?
      OnboardingSession.current_stages.key?(filters[:current_stage])
    end

    def date_from
      @date_from ||= parse_date(filters[:date_from])
    end

    def date_to
      @date_to ||= parse_date(filters[:date_to])
    end

    def parse_date(value)
      Date.iso8601(value) if value.present?
    rescue Date::Error
      nil
    end
  end
end
