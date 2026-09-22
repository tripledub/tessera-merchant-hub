# frozen_string_literal: true

module Uat
  # MH-315: drops, recreates, schema-loads and reseeds the database, so a UAT
  # deploy always leaves a clean, deterministic environment tied to the
  # current branch state instead of an accumulating one.
  #
  # Guarded by UAT_DB_RESET_ENABLED (config/initializers/uat_db_reset.rb) —
  # the same pattern as Applicants::Deletion/APPLICANT_DELETE_ENABLED and
  # Registry::SyntheticClient/SYNTHETIC_DATA_ENABLED. Never set in production;
  # it's the explicit confirmation this destructive task requires, since it
  # runs unattended from the UAT Ansible deploy, not from an interactive shell.
  #
  # db:schema:load (not db:migrate) loads the current db/schema.rb directly —
  # equivalent to a full migration replay, without running every migration in
  # sequence. It's in kyc_policies.rake's hooked task list alongside
  # db:prepare/db:migrate/db:setup, so Kyc::PolicyValiditySync (MH-305) runs
  # automatically and needs no separate call here.
  #
  # db:seed is called explicitly rather than relied on implicitly: db:prepare
  # only auto-seeds a database on its first-ever creation, not on a later
  # db:schema:load against a freshly dropped-and-recreated one.
  class DatabaseReset
    class NotEnabled < StandardError; end

    TASKS = %w[db:drop db:create db:schema:load db:seed].freeze

    def self.call(task_invoker: ->(name) { Rake::Task[name].invoke })
      new(task_invoker: task_invoker).call
    end

    def initialize(task_invoker:)
      @task_invoker = task_invoker
    end

    def call
      unless enabled?
        raise NotEnabled, "UAT_DB_RESET_ENABLED is not set — refusing to reset the database"
      end

      TASKS.each { |task| @task_invoker.call(task) }
    end

    private

    def enabled?
      Rails.application.config.x.uat_db_reset_enabled
    end
  end
end
