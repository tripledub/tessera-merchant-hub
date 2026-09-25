# frozen_string_literal: true

namespace :kyc do
  namespace :synthetic do
    desc "MH-309: reseed Synthetic::Persona records from config/synthetic/personas/*.yml"
    task seed: :environment do
      count = Synthetic::PersonaSeed.call
      puts "Synthetic personas seeded: #{count} file(s) processed"
    end
  end
end
