# frozen_string_literal: true

module Onboarding
  class ConversationsController < Portal::BaseController
    layout "onboarding"

    before_action :set_onboarding_session

    def show
      @messages = ordered_messages
    end

    def create
      StreamOnboardingResponseJob.perform_later(@onboarding_session.id, message_param)
      head :ok
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
  end
end
