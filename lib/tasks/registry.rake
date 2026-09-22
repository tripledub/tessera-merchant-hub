# frozen_string_literal: true

namespace :registry do
  desc "MH-303: backfill director date of birth (month/year) from stored raw_response onto existing registry profiles"
  task backfill_director_dob: :environment do
    result = Registry::DirectorDobBackfill.call
    puts "Registry director DOB backfill: #{result.directors_updated} directors updated, " \
      "#{result.principals_updated} principals updated"
  end
end
