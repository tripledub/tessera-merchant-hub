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
                             :awaiting_confirmation) do
      def initialize(awaiting_confirmation: [], **kwargs)
        super(awaiting_confirmation: awaiting_confirmation, **kwargs)
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

      # True for any status that should stop an Applicant completing
      # automated review without staff involvement — i.e. everything except
      # `met` and `not_applicable`. `confirmation_required` still blocks
      # here; the distinction it carries is *how* it should be labelled
      # (awaiting staff review), not *whether* it blocks.
      def blocks_automated_completion?
        unmet? || confirmation_required?
      end
    end
  end
end
