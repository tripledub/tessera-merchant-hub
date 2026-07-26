# frozen_string_literal: true

module Onboarding
  class DocumentDeferralsController < Portal::BaseController
    def create
      @session = current_applicant.onboarding_session
      service = Onboarding::DocumentCollectionService.new(@session)
      index = params.require(:index).to_i
      @deferred_item = index.negative? ? nil : service.defer_item!(index)
      post_messages(service) if @deferred_item

      respond_to(&:turbo_stream)
    end

    private

    def post_messages(service)
      @bot_message = OnboardingMessage.create!(
        onboarding_session: @session,
        role: :bot,
        content: "Noted — you can upload #{@deferred_item['label']} later. Let's continue.",
        stage: "document_collection"
      )

      return unless service.chat_can_continue?

      remaining = service.deferred_items.size
      @completion_message = OnboardingMessage.create!(
        onboarding_session: @session,
        role: :bot,
        content: "You're all set for now — #{remaining} #{'document'.pluralize(remaining)} still needed " \
                 "before KYC can be signed off. Come back any time to finish uploading.",
        stage: "document_collection"
      )
    end
  end
end
