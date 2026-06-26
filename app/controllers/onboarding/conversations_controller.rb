# frozen_string_literal: true

module Onboarding
  class ConversationsController < Portal::BaseController
    layout "onboarding"

    before_action :set_onboarding_session

    def show
      @messages = ordered_messages
    end

    def create
      previous_applicant_message = @onboarding_session.onboarding_messages.applicant.order(:created_at).last
      previous_bot_message = @onboarding_session.onboarding_messages.bot.order(:created_at).last
      result = Onboarding::ConversationEngine.respond(
        session: @onboarding_session,
        user_message: message_param
      )
      @messages = ordered_messages
      @applicant_message = latest_applicant_message_after(previous_applicant_message)
      @bot_message = latest_bot_message_after(previous_bot_message) || transient_bot_message(result.fetch(:bot_message))
      broadcast_bot_message

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

    def latest_bot_message_after(previous_bot_message)
      scope = @onboarding_session.onboarding_messages.bot.order(:created_at)
      return scope.last if previous_bot_message.blank?

      scope.where.not(id: previous_bot_message.id).last
    end

    def latest_applicant_message_after(previous_applicant_message)
      scope = @onboarding_session.onboarding_messages.applicant.order(:created_at)
      return scope.last if previous_applicant_message.blank?

      scope.where.not(id: previous_applicant_message.id).last
    end

    def broadcast_bot_message
      return unless @bot_message.persisted?

      Turbo::StreamsChannel.broadcast_append_to(
        @onboarding_session,
        target: "onboarding_messages",
        partial: "onboarding/conversations/message",
        locals: { message: @bot_message }
      )
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
