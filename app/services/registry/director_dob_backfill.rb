# frozen_string_literal: true

module Registry
  # MH-303 (AC6): registry_directors rows created before this feature shipped
  # have no date_of_birth_month/year, because Registry::CompaniesHouseUkClient
  # and Registry::SyntheticClient didn't map it yet. Every Registry::Profile
  # already stores the full raw officers response, so this re-parses that
  # (never a new Companies House call) to fill in the gap on both the director
  # row and any matching registry-fetched principal that still lacks a full
  # date of birth.
  #
  # Matches a director to its profile's directors by array position against
  # raw_response["officers"]["items"] (the same order Registry::Lookup
  # originally persisted them in) rather than by name, since a name isn't
  # guaranteed unique within a company's officer list.
  class DirectorDobBackfill
    Result = Data.define(:directors_updated, :principals_updated)

    def self.call
      new.call
    end

    def call
      directors_updated = 0
      principals_updated = 0

      Registry::Profile.find_each do |profile|
        officers = Array(profile.raw_response.dig("officers", "items"))
        directors = profile.directors.order(:created_at).to_a

        directors.each_with_index do |director, index|
          officer = officers[index]
          next if officer.blank?
          next if director.date_of_birth_month.present? || director.date_of_birth_year.present?

          dob = officer["date_of_birth"] || {}
          next if dob["month"].blank? && dob["year"].blank?

          director.update!(date_of_birth_month: dob["month"], date_of_birth_year: dob["year"])
          directors_updated += 1

          principals_updated += backfill_principal(profile, director, dob)
        end
      end

      Result.new(directors_updated: directors_updated, principals_updated: principals_updated)
    end

    private

    def backfill_principal(profile, director, dob)
      principal = profile.applicant.kyc_principals
        .active
        .registry_fetched
        .where("LOWER(name) = ?", director.name.downcase)
        .where(date_of_birth: nil, date_of_birth_month: nil, date_of_birth_year: nil)
        .first
      return 0 unless principal

      principal.update!(date_of_birth_month: dob["month"], date_of_birth_year: dob["year"])
      1
    end
  end
end
