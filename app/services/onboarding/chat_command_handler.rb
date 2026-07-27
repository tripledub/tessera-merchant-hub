# frozen_string_literal: true

module Onboarding
  module ChatCommandHandler
    module_function

    def call(session:, stage:, command:)
      case command
      when :help then respond_with(session, stage, I18n.t("onboarding.chat_commands.help"))
      when :save then respond_with(session, stage, I18n.t("onboarding.chat_commands.save"))
      when :skip then handle_skip(session, stage)
      end
    end

    def handle_skip(session, stage)
      unless stage == :document_collection
        return respond_with(session, stage, I18n.t("onboarding.chat_commands.skip_not_available"))
      end

      collection_service = Onboarding::DocumentCollectionService.new(session)
      outstanding = collection_service.outstanding_items
      return respond_with(session, stage, I18n.t("onboarding.chat_commands.nothing_to_skip")) if outstanding.empty?

      ActiveRecord::Base.transaction do
        item = collection_service.defer_item!(outstanding.first["index"])
        break respond_with(session, stage, I18n.t("onboarding.chat_commands.nothing_to_skip")) if item.nil?

        respond_with(session, stage, I18n.t("onboarding.chat_commands.skip_deferred", label: item["label"]))
      end
    end
    private_class_method :handle_skip

    def respond_with(session, stage, bot_message)
      OnboardingMessage.create!(
        onboarding_session: session,
        role: :bot,
        content: bot_message,
        stage: stage.to_s
      )

      { bot_message: bot_message, extracted_data: {}, stage_changed: false }
    end
    private_class_method :respond_with
  end
end
