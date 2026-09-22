# frozen_string_literal: true

namespace :db do
  desc "MH-315: drop, recreate, schema-load and reseed the database. UAT_DB_RESET_ENABLED must be set; never set it in production."
  task reset_and_seed: :environment do
    Uat::DatabaseReset.call
    puts "Database reset and seeded."
  rescue Uat::DatabaseReset::NotEnabled => e
    abort(e.message)
  end
end
