# frozen_string_literal: true

module Onboarding
  # MH-417: after the applicant has confirmed the registry's match for their
  # company, the chat offers the people the registry lists one at a time, so they
  # confirm or dispute each instead of typing them in again. Fixed messages with
  # Yes/No buttons, not LLM turns.
  #
  # Individuals only: active directors and active individual PSCs, one entry per
  # person (a director who is also a PSC is both). Secretaries and corporate PSCs
  # are mentioned, never created. State lives in stage_data["registry_people"]:
  # the queue, the position in it, and whether the applicant is being asked Yes/No
  # ("offering") or for the person's missing details ("collecting").
  module RegistryPeople
    KEY = "registry_people"
    STAGE = "directors_ubos"
    TITLES = %w[mr mrs ms miss mx dr prof professor sir dame lord lady].freeze
    PERSON_KINDS = { "Registry::Director" => "director",
                     "Registry::PersonWithSignificantControl" => "shareholder" }.freeze

    module_function

    # The opening message for the directors stage when there are registry people to
    # offer, nil when there are none (the stage then starts as it always has).
    def begin!(session)
      return if session.stage_data[KEY].present?

      profile = confirmed_profile(session)
      return unless profile

      queue = unmatched_people(session, profile)
      state = queue.empty? ? "done" : "offering"
      session.update!(stage_data: session.stage_data.merge(
        KEY => { "state" => state, "queue" => queue, "position" => 0 }
      ))
      return if queue.empty?

      [ extras_line(profile), offer(queue.first) ].compact.join("\n\n")
    end

    def offering?(session)
      Onboarding::StateMachine.current_stage(session) == :directors_ubos && state(session) == "offering"
    end

    # Buttons show only when the latest message is the assistant's: while the
    # applicant's own message is last, a reply is in flight.
    def awaiting_answer?(session)
      offering?(session) && session.onboarding_messages.order(:created_at, :id).last&.bot? == true
    end

    def confirm!(session)
      return unless offering?(session)

      person = current_person(session)
      seed_item(session, person)
      update_state(session, "state" => "collecting")
      bot_reply(session, details_question(person))
    end

    def decline!(session)
      return unless offering?(session)

      person = current_person(session)
      record_dispute!(session, person)
      bot_reply(session, [ I18n.t("onboarding.registry_people.declined"), next_message(session) ].join("\n\n"))
    end

    # After the chat has captured a reply: when the person being collected has been
    # completed, moves on to the next one. Returns the message, or nil.
    def progress!(session)
      return unless state(session) == "collecting" && completed?(session, current_person(session))

      next_message(session)
    end

    # A completed registry person is a principal with registry provenance, and a
    # date of birth that disagrees with the registry's month or year is flagged.
    def record_confirmed!(session, principal, item)
      person = person_for(session, item["registry_person"])
      return unless person

      profile = confirmed_profile(session)
      corroborate!(principal, profile)
      flag_date_of_birth!(session.applicant, principal, person, item["date_of_birth"])
    end

    # "SHORT, Albert Edward" and "Mr Albert Edward Short" are the same person.
    def display_name(raw)
      name = raw.to_s.strip
      name = name.split(",", 2).reverse.map(&:strip).join(" ") if name.include?(",")
      words = name.split.reject { |word| TITLES.include?(word.downcase.delete(".")) }
      words.join(" ").gsub(/[[:alpha:]]+/, &:capitalize)
    end

    def match_key(raw)
      display_name(raw).downcase
    end

    def state(session)
      session.stage_data.dig(KEY, "state")
    end
    private_class_method :state

    def queue(session)
      session.stage_data.dig(KEY, "queue") || []
    end
    private_class_method :queue

    def current_person(session)
      queue(session)[session.stage_data.dig(KEY, "position").to_i]
    end
    private_class_method :current_person

    def person_for(session, key)
      queue(session).find { |person| person["key"] == key }
    end
    private_class_method :person_for

    def update_state(session, changes)
      session.update!(stage_data: session.stage_data.merge(KEY => session.stage_data.fetch(KEY).merge(changes)))
    end
    private_class_method :update_state

    def confirmed_profile(session)
      check = session.stage_data[Onboarding::RegistryCompanyCheck::KEY]
      return unless check.is_a?(Hash) && check["state"] == "confirmed"

      session.applicant.registry_profiles.find_by(id: check["profile_id"])
    end
    private_class_method :confirmed_profile

    # The people to offer: active individuals from the registry, minus anyone the
    # applicant already has as a principal (they are corroborated instead).
    def unmatched_people(session, profile)
      existing = session.applicant.kyc_principals.active.index_by { |principal| match_key(principal.name) }
      registry_people(profile).filter_map do |person|
        principal = existing[person["key"]]
        next person unless principal

        corroborate!(principal, profile)
        nil
      end
    end
    private_class_method :unmatched_people

    def registry_people(profile)
      people = {}
      profile.directors.where(resigned_on: nil).select { |director| director.role.to_s.include?("director") }.each do |director|
        add_person(people, director.name, "director", director, director.date_of_birth_month,
                   director.date_of_birth_year, nil, "Director, appointed #{director.appointed_on&.year}".strip)
      end
      individual_pscs(profile).each do |psc|
        add_person(people, psc.name, "shareholder", psc, psc.date_of_birth_month, psc.date_of_birth_year,
                   psc.nationality, "Person with significant control")
      end
      people.values
    end
    private_class_method :registry_people

    def individual_pscs(profile)
      profile.people_with_significant_control.where(ceased_on: nil).select { |psc| psc.kind.to_s.start_with?("individual") }
    end
    private_class_method :individual_pscs

    def add_person(people, raw_name, role, row, month, year, nationality, description)
      key = match_key(raw_name)
      person = people[key] ||= { "key" => key, "name" => display_name(raw_name), "roles" => [], "rows" => [],
                                 "descriptions" => [], "dob_month" => nil, "dob_year" => nil, "nationality" => nil }
      person["roles"] |= [ role ]
      person["rows"] << { "type" => row.class.name, "id" => row.id }
      person["descriptions"] << description
      person["dob_month"] ||= month
      person["dob_year"] ||= year
      person["nationality"] ||= nationality.presence
    end
    private_class_method :add_person

    def role_for(person)
      person["roles"].sort == %w[director shareholder] ? "both" : person["roles"].first
    end
    private_class_method :role_for

    def offer(person)
      role = I18n.t("onboarding.registry_people.roles.#{role_for(person)}")
      I18n.t("onboarding.registry_people.offer", name: person["name"], role: role)
    end
    private_class_method :offer

    def extras_line(profile)
      secretaries = profile.directors.where(resigned_on: nil).count { |director| secretary_only?(director) }
      corporate = profile.people_with_significant_control.where(ceased_on: nil).count do |psc|
        !psc.kind.to_s.start_with?("individual")
      end
      parts = []
      parts << I18n.t("onboarding.registry_people.extras.secretaries", count: secretaries) if secretaries.positive?
      parts << I18n.t("onboarding.registry_people.extras.corporate_owners", count: corporate) if corporate.positive?
      return if parts.empty?

      I18n.t("onboarding.registry_people.extras.line", things: parts.to_sentence)
    end
    private_class_method :extras_line

    def secretary_only?(director)
      director.role.to_s.include?("secretary") && !director.role.to_s.include?("director")
    end
    private_class_method :secretary_only?

    # The person becomes the stage's current item, so the existing loop asks for
    # whatever is still missing (the date of birth, and the nationality when the
    # registry has none) and creates the principal when it is complete.
    def seed_item(session, person)
      item = { "full_name" => person["name"], "role" => role_for(person), "registry_person" => person["key"] }
      item["nationality"] = person["nationality"] if person["nationality"]
      payload = session.stage_data.fetch(STAGE, {}).merge("current_item" => item)
      session.update!(stage_data: session.stage_data.merge(STAGE => payload))
    end
    private_class_method :seed_item

    def details_question(person)
      if person["nationality"]
        I18n.t("onboarding.registry_people.details_dob", name: person["name"])
      else
        I18n.t("onboarding.registry_people.details_dob_nationality", name: person["name"])
      end
    end
    private_class_method :details_question

    def completed?(session, person)
      Array(session.stage_data.dig(STAGE, "items")).any? { |item| item["registry_person"] == person["key"] }
    end
    private_class_method :completed?

    def next_message(session)
      position = session.stage_data.dig(KEY, "position").to_i + 1
      person = queue(session)[position]
      update_state(session, "position" => position, "state" => person ? "offering" : "done")
      person ? offer(person) : I18n.t("onboarding.registry_people.done")
    end
    private_class_method :next_message

    def record_dispute!(session, person)
      person["rows"].each do |row|
        conflict = session.applicant.data_conflicts.status_open.find_or_initialize_by(
          record_type: row["type"], record_id: row["id"], field: "involvement"
        )
        conflict.update!(held_value: held_description(person, row), held_source: :registry,
                         held_provider: provider_for(session),
                         proposed_value: I18n.t("onboarding.registry_people.disputed_value"),
                         proposed_source: :applicant_declared, detected_at: Time.current)
      end
    end
    private_class_method :record_dispute!

    def held_description(person, row)
      index = person["rows"].index(row)
      "#{person['name']}: #{person['descriptions'][index]}"
    end
    private_class_method :held_description

    def provider_for(session)
      profile = confirmed_profile(session)
      Registry::Lookup.provider_for(profile.jurisdiction) if profile
    end
    private_class_method :provider_for

    def corroborate!(principal, profile)
      Provenance::Records.record!(applicant: principal.applicant, record: principal, source: :registry,
                                  provider: Registry::Lookup.provider_for(profile.jurisdiction),
                                  retrieved_at: profile.fetched_at)
    end
    private_class_method :corroborate!

    def flag_date_of_birth!(applicant, principal, person, given)
      date = Date.iso8601(given.to_s)
      month, year = person.values_at("dob_month", "dob_year")
      return if (month.nil? || month == date.month) && (year.nil? || year == date.year)

      conflict = applicant.data_conflicts.status_open.find_or_initialize_by(
        record_type: principal.class.name, record_id: principal.id, field: "date_of_birth"
      )
      conflict.update!(held_value: format("%<month>02d/%<year>d", month: month || 0, year: year || 0),
                       held_source: :registry, proposed_value: date.iso8601, proposed_source: :applicant_declared,
                       detected_at: Time.current)
    rescue ArgumentError
      nil
    end
    private_class_method :flag_date_of_birth!

    def bot_reply(session, content)
      session.onboarding_messages.create!(role: :bot, content: content, stage: STAGE)
    end
    private_class_method :bot_reply
  end
end
