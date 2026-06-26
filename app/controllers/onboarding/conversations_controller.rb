# frozen_string_literal: true

module Onboarding
  class ConversationsController < Portal::BaseController
    layout "onboarding"

    before_action :set_onboarding_session

    def show
      @messages = ordered_messages
    end

    def create
      result = Onboarding::ConversationEngine.respond(
        session: @onboarding_session,
        user_message: message_param
      )
      @messages = ordered_messages
      @bot_message = @messages.bot.last || transient_bot_message(result.fetch(:bot_message))

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to portal_onboarding_path }
      end
    end

    private

    def set_onboarding_session
      @onboarding_session = current_applicant.onboarding_session || current_applicant.create_onboarding_session!
    end

    def ordered_messages
      @onboarding_session.onboarding_messages.order(:created_at)
    end

    def message_param
      params.require(:message)
    end

    def transient_bot_message(content)
      @onboarding_session.onboarding_messages.build(
        role: :bot,
        content: content,
        stage: @onboarding_session.current_stage,
        created_at: Time.current
      )
    end
  end
end
