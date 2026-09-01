# frozen_string_literal: true

namespace :kyc do
  namespace :policies do
    desc "Validate deployed KYC policies and synchronize immutable validity versions"
    task sync: :environment do
      result = Kyc::PolicyValiditySync.call
      puts "KYC policies synchronized: #{result.fetch(:created)} created, #{result.fetch(:unchanged)} unchanged"
    end
  end
end
