# frozen_string_literal: true

module Kyc
  module ExecutiveSummary
    class NarrativeGenerator
      class Error < StandardError; end

      def self.call(applicant, force: false)
        new(applicant).call(force: force)
      end

      def initialize(applicant)
        @applicant = applicant
      end

      def call(force: false)
        return cached_narrative unless force || cached_narrative.nil?

        data = DataAssembler.call(@applicant)
        prompt = build_prompt(data)

        narrative = Kyc::Inference.adapter.generate(prompt: prompt)
        raise Error, "Expected Hash response, got #{narrative.class}" unless narrative.is_a?(Hash)

        @applicant.update!(
          executive_narrative: narrative,
          executive_narrative_generated_at: Time.current
        )

        narrative
      rescue Kyc::Inference::Error => e
        raise Error, "Narrative generation failed: #{e.message}"
      end

      private

      def cached_narrative
        @applicant.executive_narrative
      end

      def build_prompt(data)
        <<~PROMPT
          You are a KYC compliance analyst. Based on the structured due diligence data below,
          generate a concise executive summary for internal review.

          Return ONLY valid JSON — no explanation, no markdown fences.

          Use this exact structure:
          {
            "executive_overview": "A 2-3 sentence summary of the applicant's corporate structure, key individuals, and overall compliance posture.",
            "risk_factors": ["Each identified risk as a separate string in this array"],
            "recommended_actions": ["Each recommended action as a separate string"],
            "risk_assessment": "low, medium, or high"
          }

          Rules:
          - Be factual — base everything on the data provided, do not speculate
          - Flag nominee structures, unresolved ownership chains, and cross-reference discrepancies as risks
          - Flag missing compliance documentation as recommended actions
          - Consider the number and severity of warnings when assessing overall risk
          - Use plain English suitable for a non-technical compliance reviewer

          Due diligence data:
          #{data.to_json}
        PROMPT
      end
    end
  end
end
