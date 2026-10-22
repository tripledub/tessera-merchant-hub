# frozen_string_literal: true

module Onboarding
  # MH-399: suggested answers shown as chips under the chat. Which chips to show
  # is derived from the session (what is still missing, who spoke last), never
  # from the wording of the assistant's message: the model writes that, the
  # server only knows the stage and the missing fields.
  #
  # Two questions have chips (MH-391): the company type, then the country. A chip
  # with kind :answer is sent as the applicant's reply (the same text they could
  # have typed); :other only prompts them to type.
  module QuickReplies
    Option = Data.define(:field, :key, :label, :kind, :icon)

    COUNTRY_KEYS = %i[united_kingdom malta cyprus].freeze
    # The flag shown on each country chip (app/assets/images/flags); Other gets a globe.
    COUNTRY_ICONS = { united_kingdom: "gb", malta: "mt", cyprus: "cy", other: "globe" }.freeze
    CHIP_FIELDS = %i[company_type country_of_incorporation].freeze

    module_function

    def for(session)
      case question(session)
      when :company_type
        Onboarding::CompanyTypes::KEYS.map { |key| company_type_option(key.to_sym) }
      when :country_of_incorporation
        COUNTRY_KEYS.map { |key| country_option(key, :answer) } + [ country_option(:other, :other) ]
      else
        []
      end
    end

    # The field the chips answer, when the next thing to ask has chips. The latest
    # message must be the assistant's: while the applicant's own message is last a
    # reply is in flight, and before the first message the confirmation buttons (or
    # the welcome message) are on screen. While the registry match waits for its
    # Yes or No, those buttons are the only thing to answer.
    def question(session)
      return unless Onboarding::StateMachine.current_stage(session) == :company_info

      field = Onboarding::StateMachine.missing_fields(session).first
      return unless CHIP_FIELDS.include?(field)
      return if Onboarding::RegistryCompanyCheck.pending?(session)

      field if session.onboarding_messages.order(:created_at, :id).last&.bot?
    end

    def company_type_option(key)
      Option.new(field: :company_type, key: key, label: Onboarding::CompanyTypes.label(key), kind: :answer, icon: nil)
    end
    private_class_method :company_type_option

    def country_option(key, kind)
      Option.new(field: :country_of_incorporation, key: key,
                 label: I18n.t("onboarding.quick_replies.country.#{key}"), kind: kind, icon: COUNTRY_ICONS.fetch(key))
    end
    private_class_method :country_option
  end
end
