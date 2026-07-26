# frozen_string_literal: true

module Onboarding
  class DocumentDeferralsController < Portal::BaseController
    def create
      @session = current_applicant.onboarding_session || current_applicant.create_onboarding_session!
      @collection_service = Onboarding::DocumentCollectionService.new(@session)
      index = valid_index(params[:index])
      @deferred_item = index && @collection_service.defer_item!(index)
      @completion_message = post_messages if @deferred_item

      respond_to(&:turbo_stream)
    end

    private

    def valid_index(raw_index)
      return nil unless raw_index.to_s.match?(/\A\d+\z/)

      raw_index.to_i
    end

    def post_messages
      @bot_message = OnboardingMessage.create!(
        onboarding_session: @session,
        role: :bot,
        content: "Noted — you can upload #{@deferred_item['label']} later. Let's continue.",
        stage: "document_collection"
      )

      return unless @collection_service.chat_can_continue?

      remaining = @collection_service.deferred_items.size
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
