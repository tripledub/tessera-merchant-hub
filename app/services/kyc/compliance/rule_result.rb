# frozen_string_literal: true

module Kyc
  module Compliance
    # `awaiting_confirmation` (MH-198) lists requirements satisfied only by a
    # document whose validity assessment is `confirmation_required` — data
    # exists, but no automated outcome can be reached without staff
    # confirming a date. That is a DISTINCT status from `unmet`: staff can
    # resolve it without new evidence, so it must never collapse into
    # "rejected" for callers such as MH-200 that need to render it
    # differently (e.g. "awaiting staff review" rather than a rejection).
    RuleResult = Data.define(:rule_name, :entity, :status, :requirements, :satisfied, :missing,
                             :awaiting_confirmation, :requirement_id, :title, :guidance, :outcome) do
      def initialize(awaiting_confirmation: [], requirement_id: nil, title: nil, guidance: nil,
                     outcome: :blocking, **kwargs)
        super(
          awaiting_confirmation: awaiting_confirmation,
          requirement_id: requirement_id,
          title: title,
          guidance: guidance,
          outcome: outcome,
          **kwargs
        )
      end

      def met?
        status == :met
      end

      def unmet?
        status == :unmet
      end

      def not_applicable?
        status == :not_applicable
      end

      def confirmation_required?
        status == :confirmation_required
      end

      # Blocking outcomes stop automated review when unmet or awaiting staff
      # confirmation. Warning outcomes remain visible without preventing
      # completion.
      def blocks_automated_completion?
        outcome.to_sym == :blocking && (unmet? || confirmation_required?)
      end
    end
  end
end
