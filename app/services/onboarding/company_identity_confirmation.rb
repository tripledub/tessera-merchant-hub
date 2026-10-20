# frozen_string_literal: true

module Onboarding
  # Opens the chat by confirming the company name and number already on the
  # application (typically entered through the form), instead of asking for
  # them again. A fixed message, not an LLM turn: the answer is a yes/no button.
  #
  # A business the PSP added has a name but no company name the applicant has
  # declared yet (MH-415). The PSP's name is offered for them to confirm, and
  # confirming makes it their own answer, so the chat and the form agree.
  module CompanyIdentityConfirmation
    CHECK_KEY = "company_identity_check"
    STAGE_KEY = "company_info"

    module_function

    # The company name to confirm: the applicant's own, else the name the PSP gave.
    def company_name(session)
      applicant = session.applicant
      applicant.company_name.presence || applicant.name.presence
    end

    def pending?(session)
      session.stage_data[CHECK_KEY].blank? &&
        session.onboarding_messages.none? &&
        company_name(session).present?
    end

    def prompt(session)
      applicant = session.applicant
      number = applicant.company_number.presence
      company = "**#{company_name(session)}**"
      company += ", company number **#{number}**" if number

      "I have your company as #{company}. Is this correct?"
    end

    def confirm!(session)
      declare_company_name!(session)
      session.update!(stage_data: with_company_identity(session))
      reply(session, remaining_questions(session))
    end

    def decline!(session)
      session.update!(stage_data: session.stage_data.merge(CHECK_KEY => "declined"))
      reply(session, "No problem, let's start again. Please tell us the name of your business.")
    end

    def with_company_identity(session)
      applicant = session.applicant
      company_info = session.stage_data.fetch(STAGE_KEY, {}).merge(
        "company_name" => company_name(session),
        "registration_number" => applicant.company_number.presence
      ).compact

      session.stage_data.merge(STAGE_KEY => company_info, CHECK_KEY => "confirmed")
    end
    private_class_method :with_company_identity

    # Saying yes to the PSP's name makes it the applicant's own answer. The PSP's
    # own name is never touched.
    def declare_company_name!(session)
      return if session.applicant.company_name.present?

      Provenance::CompanyFields.apply!(applicant: session.applicant, field: "company_name",
                                       value: company_name(session), source: :applicant_declared)
    end
    private_class_method :declare_company_name!

    def remaining_questions(session)
      missing = Onboarding::StateMachine.missing_fields(session).map { |field| field.to_s.humanize }
      return "Thanks, that's everything I need for your company details." if missing.empty?

      "Thanks. To finish your company details I still need: #{missing.join(', ')}."
    end
    private_class_method :remaining_questions

    def reply(session, content)
      session.onboarding_messages.create!(role: :bot, content: content, stage: session.current_stage)
    end
    private_class_method :reply
  end
end
