# frozen_string_literal: true

module Onboarding
  # MH-391: the kinds of company the chat offers as chips, how free text is mapped
  # onto them, and which ones a company registry can look up.
  module CompanyTypes
    KEYS = %w[limited_company plc llp sole_trader partnership other].freeze
    # A registry holds these; a sole trader or a partnership has no company number.
    REGISTRY_SEARCHABLE = %w[limited_company plc llp].freeze

    SYNONYMS = {
      "limited company" => "limited_company", "private limited company" => "limited_company",
      "ltd" => "limited_company", "limited" => "limited_company", "private limited" => "limited_company",
      "public limited company" => "plc", "public limited" => "plc",
      "limited liability partnership" => "llp",
      "sole trader" => "sole_trader", "sole proprietor" => "sole_trader", "sole proprietorship" => "sole_trader",
      "self employed" => "sole_trader", "self-employed" => "sole_trader",
      "general partnership" => "partnership"
    }.freeze

    module_function

    # A key from a key, a label or common wording; nil when it is none of them.
    def normalize(value)
      text = value.to_s.strip.downcase.tr("_", " ").squeeze(" ")
      return if text.blank?

      key = text.tr(" ", "_")
      return key if KEYS.include?(key)

      SYNONYMS[text] || (KEYS.find { |candidate| I18n.t("onboarding.company_types.#{candidate}").downcase == text })
    end

    def registry_searchable?(value)
      REGISTRY_SEARCHABLE.include?(normalize(value))
    end

    def label(key)
      I18n.t("onboarding.company_types.#{key}")
    end
  end
end
