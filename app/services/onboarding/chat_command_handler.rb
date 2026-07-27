# frozen_string_literal: true

module Onboarding
  module ChatCommandHandler
    HELP_MESSAGE = <<~TEXT.strip
      Here's what I can help with:
      - **help** — show this message
      - **save** or **save and quit** — your progress is saved automatically, so this just confirms it
      - **skip** or **next** — skip an outstanding document upload, where available
    TEXT

    SAVE_MESSAGE = "You're all saved — your progress is kept automatically as you go. " \
      "Come back any time and pick up where you left off."

    SKIP_NOT_AVAILABLE_MESSAGE = "Skipping isn't available at this stage yet — let's finish this step first."

    NOTHING_TO_SKIP_MESSAGE = "There's nothing left to skip right now."

    module_function

    def call(session:, stage:, command:)
      case command
      when :help then respond_with(session, stage, HELP_MESSAGE)
      when :save then respond_with(session, stage, SAVE_MESSAGE)
      when :skip then handle_skip(session, stage)
      end
    end

    def handle_skip(session, stage)
      return respond_with(session, stage, SKIP_NOT_AVAILABLE_MESSAGE) unless stage == :document_collection

      collection_service = Onboarding::DocumentCollectionService.new(session)
      outstanding = collection_service.outstanding_items
      return respond_with(session, stage, NOTHING_TO_SKIP_MESSAGE) if outstanding.empty?

      ActiveRecord::Base.transaction do
        item = collection_service.defer_item!(outstanding.first["index"])
        break respond_with(session, stage, NOTHING_TO_SKIP_MESSAGE) if item.nil?

        respond_with(session, stage, "Noted — you can upload #{item['label']} later. Let's continue.")
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
