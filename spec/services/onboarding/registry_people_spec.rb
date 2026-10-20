# frozen_string_literal: true

require "rails_helper"

# MH-417: the registry's directors and PSCs are offered one at a time after the
# company match is confirmed. Synthetic people only.
RSpec.describe Onboarding::RegistryPeople do
  let(:applicant) { create(:applicant, company_name: "Acme Widgets", registry_jurisdiction: "gb") }
  let(:profile) do
    create(:registry_profile, applicant: applicant, company_name: "ACME WIDGETS LIMITED", jurisdiction: "gb")
  end
  let(:check) { { "state" => "confirmed", "profile_id" => profile.id } }
  let(:session) do
    create(:onboarding_session, applicant: applicant, current_stage: :directors_ubos,
                                stage_data: { "company_info" => { "company_name" => "Acme Widgets" },
                                              Onboarding::RegistryCompanyCheck::KEY => check })
  end

  def director(name, role: "director", **attributes)
    create(:registry_director, registry_profile: profile, name: name, role: role, **attributes)
  end

  def psc(name, **attributes)
    create(:registry_person_with_significant_control, registry_profile: profile, name: name, **attributes)
  end

  def people
    session.reload.stage_data.dig("registry_people", "queue").map { |person| person["name"] }
  end

  describe ".display_name / .match_key" do
    it "turns Companies House's SURNAME, Forename into Forename Surname" do
      expect(described_class.display_name("SHORT, Albert Edward")).to eq("Albert Edward Short")
    end

    it "drops titles and handles apostrophes and hyphens" do
      expect(described_class.display_name("Mr Albert Edward Short")).to eq("Albert Edward Short")
      expect(described_class.display_name("O'NEILL-SMITH, Jane")).to eq("Jane O'Neill-Smith")
    end

    it "gives the same key to the director and PSC entries of one person" do
      expect(described_class.match_key("SHORT, Albert Edward")).to eq(described_class.match_key("Mr Albert Edward Short"))
    end
  end

  describe ".begin!" do
    it "offers an active director as a director, with the opening question" do
      director("DOE, Jane")

      message = described_class.begin!(session)

      expect(message).to eq("The registry lists **Jane Doe** as a director. Is that you or someone involved in the business?")
    end

    it "offers an individual PSC as a person with significant control" do
      psc("Mr Albert Edward Short")

      expect(described_class.begin!(session)).to include("**Albert Edward Short** as a person with significant control")
    end

    it "offers a director who is also a PSC once, as both" do
      director("SHORT, Albert Edward")
      psc("Mr Albert Edward Short")

      expect(described_class.begin!(session)).to include("as a director and person with significant control")
      expect(people).to eq([ "Albert Edward Short" ])
    end

    it "does not offer resigned directors, ceased PSCs, secretaries or corporate PSCs" do
      director("DOE, Jane")
      director("OLD, Sam", resigned_on: Date.new(2022, 1, 1))
      director("CLERK, Cleo", role: "secretary")
      psc("Former Owner", ceased_on: Date.new(2022, 1, 1))
      psc("Holdings Limited", kind: "corporate-entity-person-with-significant-control")

      described_class.begin!(session)

      expect(people).to eq([ "Jane Doe" ])
    end

    it "names the secretary and corporate owner in one line" do
      director("DOE, Jane")
      director("CLERK, Cleo", role: "secretary")
      psc("Holdings Limited", kind: "corporate-entity-person-with-significant-control")

      message = described_class.begin!(session)

      expect(message).to start_with("The registry also lists a secretary and a corporate owner; we'll cover owners next.")
      expect(message).to include("**Jane Doe**")
    end

    it "does not offer someone the applicant already has as a principal, and corroborates them instead" do
      director("DOE, Jane")
      director("ROE, Rita")
      existing = create(:kyc_principal, applicant: applicant, name: "Jane Doe", source: :applicant_declared)

      described_class.begin!(session)

      expect(people).to eq([ "Rita Roe" ])
      expect(Provenance::Records.source_for(existing)).to eq(:registry)
    end

    it "offers two people who share a name separately only when the names differ" do
      director("DOE, Jane")
      director("DOE, John")

      described_class.begin!(session)

      expect(people).to eq([ "Jane Doe", "John Doe" ])
    end

    it "returns nil, and starts the stage as usual, when nobody is active in the registry" do
      director("OLD, Sam", resigned_on: Date.new(2022, 1, 1))

      expect(described_class.begin!(session)).to be_nil
    end

    it "returns nil when the registry match was not confirmed" do
      director("DOE, Jane")
      session.update!(stage_data: session.stage_data.merge(Onboarding::RegistryCompanyCheck::KEY => { "state" => "declined" }))

      expect(described_class.begin!(session)).to be_nil
    end

    it "returns nil when there was no registry check at all" do
      director("DOE, Jane")
      session.update!(stage_data: { "company_info" => {} })

      expect(described_class.begin!(session)).to be_nil
    end

    it "builds the queue once, so a second call does not start again" do
      director("DOE, Jane")
      described_class.begin!(session)

      expect(described_class.begin!(session)).to be_nil
    end
  end

  describe "awaiting an answer" do
    before do
      director("DOE, Jane")
      described_class.begin!(session)
    end

    it "is true while the latest message is the assistant's, false while a reply is in flight" do
      create(:onboarding_message, onboarding_session: session, role: :bot, content: "The registry lists Jane Doe")
      expect(described_class.awaiting_answer?(session)).to be(true)

      create(:onboarding_message, onboarding_session: session, role: :applicant, content: "hello")
      expect(described_class.awaiting_answer?(session)).to be(false)
    end

    it "is false outside the directors stage" do
      create(:onboarding_message, onboarding_session: session, role: :bot, content: "x")
      session.update!(current_stage: :ownership)

      expect(described_class.awaiting_answer?(session)).to be(false)
    end
  end

  describe ".confirm!" do
    it "makes the person the current item and asks only for the date of birth and nationality of a director" do
      director("DOE, Jane")
      described_class.begin!(session)

      reply = described_class.confirm!(session)

      item = session.reload.stage_data.dig("directors_ubos", "current_item")
      expect(item).to include("full_name" => "Jane Doe", "role" => "director", "registry_person" => "jane doe")
      expect(reply.content).to eq("Thanks. What are Jane Doe's date of birth and nationality?")
      expect(Onboarding::StateMachine.missing_fields(session)).to eq(%i[date_of_birth nationality])
    end

    it "does not ask for the nationality the registry already has" do
      psc("Mr Albert Edward Short", nationality: "British")
      described_class.begin!(session)

      reply = described_class.confirm!(session)

      expect(reply.content).to eq("Thanks. What is Albert Edward Short's date of birth?")
      expect(session.reload.stage_data.dig("directors_ubos", "current_item")).to include("nationality" => "British",
                                                                                         "role" => "shareholder")
      expect(Onboarding::StateMachine.missing_fields(session)).to eq(%i[date_of_birth])
    end

    it "does nothing when no one is being offered" do
      expect(described_class.confirm!(session)).to be_nil
    end
  end

  describe "completing a confirmed person" do
    let(:person_data) { { "date_of_birth" => "1980-02-14", "nationality" => "British" } }

    before do
      director("DOE, Jane", date_of_birth_month: 2, date_of_birth_year: 1980)
      director("ROE, Rita")
      described_class.begin!(session)
      described_class.confirm!(session)
    end

    def complete_current_person(data = person_data)
      Onboarding::DataCaptureService.call(session: session, extracted_data: data)
    end

    it "creates the principal with registry provenance and no conflict when the date agrees" do
      complete_current_person

      principal = applicant.kyc_principals.find_by!(name: "Jane Doe")
      expect(principal).to have_attributes(role: "director", country: "British")
      expect(Provenance::Records.source_for(principal)).to eq(:registry)
      expect(applicant.data_conflicts).to be_empty
    end

    it "accepts a date of birth that disagrees with the registry's month or year, and records a conflict" do
      complete_current_person("date_of_birth" => "1981-02-14", "nationality" => "British")

      principal = applicant.kyc_principals.find_by!(name: "Jane Doe")
      expect(principal.date_of_birth).to eq(Date.new(1981, 2, 14))
      expect(applicant.data_conflicts.status_open.find_by!(field: "date_of_birth")).to have_attributes(
        record_type: "KycPrincipal", record_id: principal.id.to_s, held_value: "02/1980", proposed_value: "1981-02-14"
      )
    end

    it "moves on to the next person once the current one is complete, and not before" do
      expect(described_class.progress!(session)).to be_nil

      complete_current_person

      expect(described_class.progress!(session)).to include("**Rita Roe** as a director")
      expect(described_class.offering?(session)).to be(true)
    end

    it "asks whether anyone else is involved after the last person" do
      complete_current_person
      described_class.progress!(session)
      described_class.decline!(session)

      expect(session.onboarding_messages.bot.order(:created_at).last.content)
        .to include("That's everyone the registry lists. Is anyone else a director or owner of the business?")
      expect(described_class.offering?(session)).to be(false)
    end
  end

  describe ".decline!" do
    before do
      director("DOE, Jane")
      director("ROE, Rita")
      described_class.begin!(session)
    end

    it "records a conflict for staff, creates no principal and offers the next person" do
      reply = described_class.decline!(session)

      row = profile.directors.find_by!(name: "DOE, Jane")
      expect(applicant.data_conflicts.status_open.find_by!(field: "involvement")).to have_attributes(
        record_type: "Registry::Director", record_id: row.id.to_s, proposed_value: "Applicant says not involved",
        held_value: "Jane Doe: Director, appointed 2020"
      )
      expect(applicant.kyc_principals).to be_empty
      expect(reply.content).to include("No problem, I've noted that.", "**Rita Roe**")
      expect(profile.directors.count).to eq(2)
    end

    it "records a conflict on each registry row of a person who is both" do
      profile.directors.destroy_all
      director("SHORT, Albert Edward")
      psc("Mr Albert Edward Short")
      session.update!(stage_data: session.stage_data.except("registry_people"))
      described_class.begin!(session)

      described_class.decline!(session)

      expect(applicant.data_conflicts.status_open.where(field: "involvement").pluck(:record_type))
        .to contain_exactly("Registry::Director", "Registry::PersonWithSignificantControl")
    end

    it "does nothing when no one is being offered" do
      described_class.decline!(session)
      described_class.decline!(session)

      expect(described_class.decline!(session)).to be_nil
    end
  end
end
