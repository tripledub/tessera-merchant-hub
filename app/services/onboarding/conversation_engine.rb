# frozen_string_literal: true

module Onboarding
  module ConversationEngine
    module_function

    def respond(session:, user_message:, inference_adapter: Kyc::Inference.adapter)
      stage = Onboarding::StateMachine.current_stage(session)
      create_message!(session, role: :applicant, content: user_message, stage: stage)

      prompt = Onboarding::PromptBuilder.build(session: session)
      response = parse_response(inference_adapter.generate(prompt: prompt))

      ActiveRecord::Base.transaction do
        extracted_data = Onboarding::DataCaptureService.call(
          session: session,
          extracted_data: response.fetch("extracted_data")
        )
        stage_changed = advance_if_complete(session, user_message: user_message)

        create_message!(
          session,
          role: :bot,
          content: response.fetch("bot_message"),
          stage: stage,
          structured_data: extracted_data
        )

        {
          bot_message: response.fetch("bot_message"),
          extracted_data: extracted_data,
          stage_changed: stage_changed
        }
      end
    end

    def create_message!(session, role:, content:, stage:, structured_data: {})
      OnboardingMessage.create!(
        onboarding_session: session,
        role: role,
        content: content,
        stage: stage.to_s,
        structured_data: structured_data
      )
    end
    private_class_method :create_message!

    def parse_response(response)
      parsed = response.is_a?(String) ? JSON.parse(response) : response.deep_stringify_keys
      validate_response!(parsed)
      parsed
    rescue JSON::ParserError => e
      raise Kyc::Inference::Error, "Onboarding response was not valid JSON: #{e.message}"
    end
    private_class_method :parse_response

    def validate_response!(response)
      raise Kyc::Inference::Error, "Onboarding response missing bot_message" if response["bot_message"].blank?
      raise Kyc::Inference::Error, "Onboarding response missing extracted_data" unless response["extracted_data"].is_a?(Hash)
    end
    private_class_method :validate_response!

    def advance_if_complete(session, user_message:)
      return false if looping_stage?(session) && !no_more_loop_items?(user_message)
      return false unless Onboarding::StateMachine.stage_complete?(session)

      Onboarding::StateMachine.advance!(session)
      true
    end
    private_class_method :advance_if_complete

    def no_more_loop_items?(user_message)
      user_message.to_s.match?(/\b(no|none|no more|nothing else|that's all|that is all|all done)\b/i)
    end
    private_class_method :no_more_loop_items?

    def looping_stage?(session)
      %i[directors_ubos ownership jurisdictions].include?(Onboarding::StateMachine.current_stage(session))
    end
    private_class_method :looping_stage?
  end
end
