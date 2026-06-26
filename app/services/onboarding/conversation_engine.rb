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
        stage_changed = advance_if_complete(session, extracted_data: response.fetch("extracted_data"))
        bot_message = response.fetch("bot_message")
        bot_message = add_stage_transition_prompt(bot_message, session) if stage_changed

        create_message!(
          session,
          role: :bot,
          content: bot_message,
          stage: stage,
          structured_data: extracted_data
        )

        {
          bot_message: bot_message,
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

    def advance_if_complete(session, extracted_data:)
      return false if looping_stage?(session) && !done_adding_items?(extracted_data)
      return false unless Onboarding::StateMachine.stage_complete?(session)

      Onboarding::StateMachine.advance!(session)
      true
    end
    private_class_method :advance_if_complete

    def done_adding_items?(extracted_data)
      extracted_data["done_adding_items"] == true
    end
    private_class_method :done_adding_items?

    def add_stage_transition_prompt(bot_message, session)
      [ bot_message, stage_transition_prompt(session) ].compact_blank.join("\n\n")
    end
    private_class_method :add_stage_transition_prompt

    def stage_transition_prompt(session)
      case Onboarding::StateMachine.current_stage(session)
      when :directors_ubos
        "Next, let’s add the directors and beneficial owners. Please provide the first person’s full name, date of birth, nationality, and whether they are a director, shareholder/UBO, or both."
      when :ownership
        "Next, let’s map the ownership structure. Who owns or controls #{company_name(session)}, what do they own, and is the relationship equity, nominee, or contractual?"
      when :business_activity
        "Next, let’s capture the business activity. What industry is #{company_name(session)} in, and how would you describe what the business does?"
      when :jurisdictions
        "Next, let’s record operating jurisdictions. Which country should we add first, and do you have any licence type or licence number for it?"
      when :document_collection
        "Next, let’s collect supporting documents. Please use the upload button to add the requested KYC documents."
      end
    end
    private_class_method :stage_transition_prompt

    def company_name(session)
      session.stage_data.dig("company_info", "company_name").presence || "the company"
    end
    private_class_method :company_name

    def looping_stage?(session)
      %i[directors_ubos ownership jurisdictions].include?(Onboarding::StateMachine.current_stage(session))
    end
    private_class_method :looping_stage?
  end
end
