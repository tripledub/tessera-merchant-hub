# frozen_string_literal: true

module Onboarding
  # MH-391: after the company's type, country and number are known the chat looks
  # the company up and asks "is this your company?". A fixed message with Yes/No
  # buttons, not an LLM turn, so what is shown is exactly what the registry holds.
  #
  # Only a lookup of the number: no principals or ownership are created from it.
  # Nothing found, or a registry that is down, falls back to the normal questions.
  module RegistryCompanyCheck
    KEY = "registry_check"
    STAGE_KEY = "company_info"

    module_function

    def due?(session)
      applicant = session.applicant
      company_info = session.stage_data.fetch(STAGE_KEY, {})

      Onboarding::StateMachine.current_stage(session) == :company_info &&
        session.stage_data[KEY].blank? &&
        Onboarding::CompanyTypes.registry_searchable?(company_info["company_type"]) &&
        company_info["registration_number"].present? &&
        Registry::Lookup.client_class_for(applicant.registry_jurisdiction).present?
    end

    def pending?(session)
      Onboarding::StateMachine.current_stage(session) == :company_info && state(session) == "pending"
    end

    # The buttons show only when the latest message is the card (or another
    # assistant message): while the applicant's own message is last, a reply is in flight.
    def awaiting_answer?(session)
      pending?(session) && session.onboarding_messages.order(:created_at, :id).last&.bot? == true
    end

    # :found when there is a company to confirm, :failed otherwise.
    def run!(session)
      applicant = session.applicant
      number = session.stage_data.dig(STAGE_KEY, "registration_number")
      result = lookup(applicant, number)

      applicant.update!(registry_lookup_attempted_at: Time.current, registry_lookup_error: result.error_type&.to_s)
      return remember(session, "failed") && :failed unless result.success

      remember(session, "pending", "profile_id" => result.registry_profile.id)
      :found
    end

    def prompt(session)
      profile = profile(session)
      address = address_line(profile)

      I18n.t("onboarding.registry_check.prompt", name: profile.company_name, status: profile.status,
                                                   address: address, provider: provider_name(profile))
    end

    def confirm!(session)
      return unless pending?(session)

      profile = profile(session)
      save_details(session, profile)
      remember(session, "confirmed", "profile_id" => profile.id)
      answer(session, I18n.t("onboarding.registry_check.confirmed"))
    end

    def decline!(session)
      return unless pending?(session)

      remember(session, "declined")
      answer(session, I18n.t("onboarding.registry_check.declined"))
    end

    def failure_notice
      I18n.t("onboarding.registry_check.failed")
    end

    def state(session)
      session.stage_data.dig(KEY, "state")
    end
    private_class_method :state

    def lookup(applicant, number)
      Registry::Lookup.call(applicant: applicant, company_number: number, jurisdiction: applicant.registry_jurisdiction)
    rescue StandardError => e
      Rails.logger.warn("[RegistryCompanyCheck] lookup failed: #{e.class}")
      Registry::Lookup::Result.failure(:unavailable)
    end
    private_class_method :lookup

    def remember(session, state, extra = {})
      session.update!(stage_data: session.stage_data.merge(KEY => { "state" => state }.merge(extra)))
    end
    private_class_method :remember

    def profile(session)
      session.applicant.registry_profiles.find(session.stage_data.dig(KEY, "profile_id"))
    end
    private_class_method :profile

    def registered_address(profile)
      profile.addresses.find_by(kind: "registered")
    end
    private_class_method :registered_address

    def address_line(profile)
      address = registered_address(profile)
      return I18n.t("onboarding.registry_check.no_address") unless address

      [ address.line1, address.city, address.postcode ].compact_blank.join(", ")
    end
    private_class_method :address_line

    def provider_name(profile)
      if Registry::Lookup.provider_for(profile.jurisdiction) == "companies_house"
        I18n.t("onboarding.registry_check.providers.companies_house")
      else
        I18n.t("onboarding.registry_check.providers.other")
      end
    end
    private_class_method :provider_name

    def save_details(session, profile)
      applicant = session.applicant
      provider = Registry::Lookup.provider_for(profile.jurisdiction)
      { "company_name" => profile.company_name, "company_number" => profile.company_number }.each do |field, value|
        Provenance::CompanyFields.apply!(applicant: applicant, field: field, value: value, source: :registry,
                                         provider: provider, retrieved_at: profile.fetched_at)
      end

      company_info = session.stage_data.fetch(STAGE_KEY, {}).merge(
        "company_name" => profile.company_name, "registration_number" => profile.company_number,
        "registered_address" => registered_address(profile) && address_line(profile)
      ).compact
      session.update!(stage_data: session.stage_data.merge(STAGE_KEY => company_info))
    end
    private_class_method :save_details

    # The answer may have finished the company details, in which case the chat moves on.
    def answer(session, acknowledgement)
      stage = session.current_stage
      next_stage_opening = Onboarding::ConversationEngine.advance_after_fixed_reply(session)
      content = next_stage_opening ? [ acknowledgement, next_stage_opening ].join("\n\n") : "#{acknowledgement} #{remaining_questions(session)}"

      session.onboarding_messages.create!(role: :bot, content: content, stage: stage)
    end
    private_class_method :answer

    def remaining_questions(session)
      missing = Onboarding::StateMachine.missing_fields(session)
      return I18n.t("onboarding.registry_check.nothing_else") if missing.empty?

      I18n.t("onboarding.registry_check.still_needed", fields: missing.map { |field| field.to_s.humanize.downcase }.to_sentence)
    end
    private_class_method :remaining_questions
  end
end
