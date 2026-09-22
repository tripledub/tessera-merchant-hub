# frozen_string_literal: true

require "rails_helper"

# MH-303 (AC6): backfills registry_directors and matching kyc_principals from
# the raw_response already stored on each Registry::Profile — no new
# Companies House calls.
RSpec.describe Registry::DirectorDobBackfill do
  let_it_be(:applicant) { create(:applicant) }

  let(:raw_response) do
    {
      "officers" => {
        "items" => [
          { "name" => "SAMPLE, Riley", "officer_role" => "director", "date_of_birth" => { "month" => 3, "year" => 1985 } },
          { "name" => "EXAMPLE, Jordan", "officer_role" => "director" }
        ]
      }
    }
  end

  let!(:profile) { create(:registry_profile, applicant: applicant, raw_response: raw_response) }

  let!(:riley_director) do
    create(:registry_director, registry_profile: profile, name: "SAMPLE, Riley", role: "director",
      appointed_on: Date.new(2020, 1, 1))
  end
  let!(:jordan_director) do
    create(:registry_director, registry_profile: profile, name: "EXAMPLE, Jordan", role: "director",
      appointed_on: Date.new(2020, 1, 1))
  end

  def call
    described_class.call
  end

  it "backfills a director's month/year of birth from the raw response" do
    call

    expect(riley_director.reload.date_of_birth_month).to eq(3)
    expect(riley_director.reload.date_of_birth_year).to eq(1985)
  end

  it "leaves a director nil when the raw response has no date of birth for them" do
    call

    expect(jordan_director.reload.date_of_birth_month).to be_nil
    expect(jordan_director.reload.date_of_birth_year).to be_nil
  end

  it "backfills a matching registry-fetched principal that still lacks a date of birth" do
    principal = create(:kyc_principal, applicant: applicant, name: "SAMPLE, Riley", source: :registry_fetched)

    call

    expect(principal.reload.date_of_birth_month).to eq(3)
    expect(principal.reload.date_of_birth_year).to eq(1985)
  end

  it "does not touch a principal that already has a full date of birth" do
    principal = create(:kyc_principal, applicant: applicant, name: "SAMPLE, Riley", source: :registry_fetched,
      date_of_birth: Date.new(1985, 3, 17))

    call

    expect(principal.reload.date_of_birth_month).to be_nil
  end

  it "does not touch a principal that is not registry-fetched" do
    principal = create(:kyc_principal, applicant: applicant, name: "SAMPLE, Riley", source: :document_extracted)

    call

    expect(principal.reload.date_of_birth_month).to be_nil
  end

  it "is idempotent: a director already backfilled is left alone on a second run" do
    call
    riley_director.reload.update!(date_of_birth_month: 12) # simulate a hand-corrected value

    call

    expect(riley_director.reload.date_of_birth_month).to eq(12)
  end

  it "makes no Companies House network calls" do
    call

    expect(WebMock).not_to have_requested(:any, /.*/)
  end

  it "returns counts of what it updated" do
    create(:kyc_principal, applicant: applicant, name: "SAMPLE, Riley", source: :registry_fetched)

    result = call

    expect(result.directors_updated).to eq(1)
    expect(result.principals_updated).to eq(1)
  end
end
