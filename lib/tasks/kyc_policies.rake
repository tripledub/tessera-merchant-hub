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

# MH-305: publish validity policies whenever the database is prepared, migrated,
# set up, or schema-loaded, so no deploy path depends on bin/docker-entrypoint
# (UAT runs `db:prepare` under systemd and never touches it). db:schema:load is
# here for MH-315's `db:reset_and_seed`, which loads db/schema.rb directly
# rather than replaying every migration. A sync failure, such as a Conflict on
# a published version, fails the task and stops the deploy.
#
# Skipped in the test environment: CI runs `db:migrate`/`db:schema:load` there
# and specs create their own policies, which would collide with pre-published rows.
%w[db:prepare db:migrate db:setup db:schema:load].each do |name|
  Rake::Task[name].enhance do
    Rake::Task["kyc:policies:sync"].invoke unless Rails.env.test?
  end
end
