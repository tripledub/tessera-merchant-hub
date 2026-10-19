# frozen_string_literal: true

module Onboarding
  # MH-399: suggested answers shown as chips under the chat. Which chips to show
  # is derived from the session (what is still missing, who spoke last), never
  # from the wording of the assistant's message: the model writes that, the
  # server only knows the stage and the missing fields.
  #
  # Today there is one question with chips, the company's country of
  # incorporation. A chip with kind :answer is sent as the applicant's reply
  # (the same text they could have typed); :other only prompts them to type.
  module QuickReplies
    Option = Data.define(:key, :label, :kind)

    COUNTRY_KEYS = %i[united_kingdom malta cyprus].freeze

    module_function

    def for(session)
      return [] unless country_question?(session)

      COUNTRY_KEYS.map { |key| option(key, :answer) } + [ option(:other, :other) ]
    end

    # The country is the last company_info field, so "it is the only thing
    # missing" also means every earlier question has been answered. The latest
    # message must be the assistant's: while the applicant's own message is
    # last a reply is in flight, and before the first message the confirmation
    # buttons (or the welcome message) are on screen.
    def country_question?(session)
      Onboarding::StateMachine.current_stage(session) == :company_info &&
        Onboarding::StateMachine.missing_fields(session) == [ :country_of_incorporation ] &&
        session.onboarding_messages.order(:created_at, :id).last&.bot?
    end
    private_class_method :country_question?

    def option(key, kind)
      Option.new(key: key, label: I18n.t("onboarding.quick_replies.country.#{key}"), kind: kind)
    end
    private_class_method :option
  end
end
