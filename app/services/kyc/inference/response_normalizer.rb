# frozen_string_literal: true

module Kyc
  module Inference
    # Claude sometimes wraps JSON responses in a markdown code fence despite
    # being told not to, and can add leading/trailing commentary or (if cut
    # off mid-response) never close the fence at all. Shared by AiFallback
    # and ClaudeAdapter so both classification and extraction tolerate this
    # the same way (MH-172).
    module ResponseNormalizer
      FENCE_PATTERN = /```(?:json)?\s*(.*?)\s*```/m

      module_function

      def extract_json(text)
        stripped = text.strip
        fenced = stripped.match(FENCE_PATTERN)&.[](1)
        return fenced if fenced.present?

        best_effort_object(stripped) || stripped
      end

      # Fallback for an unclosed/truncated fence: grab the outermost {...}
      # span rather than failing outright. Not a guarantee of valid JSON —
      # JSON.parse still does the real validation.
      def best_effort_object(text)
        start = text.index("{")
        finish = text.rindex("}")
        return nil unless start && finish && finish > start

        text[start..finish]
      end
    end
  end
end
