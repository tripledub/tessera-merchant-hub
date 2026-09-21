# frozen_string_literal: true

module Kyc
  module Compliance
    # MH-251: one place that decides how a readiness outcome is worded and
    # coloured, so the Overview card, the Summary tab and the executive summary
    # PDF cannot drift apart for the same applicant.
    module ReadinessOutcome
      BADGE_COLOURS = {
        compliant: :green,
        not_assessable: :gray,
        requires_review: :amber,
        non_compliant: :red
      }.freeze

      def self.label(outcome)
        I18n.t("kyc.compliance.readiness_outcome.label.#{outcome}")
      end

      def self.description(outcome)
        I18n.t("kyc.compliance.readiness_outcome.description.#{outcome}")
      end

      def self.badge_colour(outcome)
        BADGE_COLOURS.fetch(outcome)
      end
    end
  end
end
