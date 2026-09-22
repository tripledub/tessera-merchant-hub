# frozen_string_literal: true

# UAT-only gate for the destructive `db:reset_and_seed` task (MH-315).
# Production never sets UAT_DB_RESET_ENABLED, so the task stays inert there
# with no environment-specific code branch.
#
# Note: there's no Rails.env-based safety net on top of this — UAT and (once
# provisioned) production both run RAILS_ENV=production (see tessera-infra),
# so Rails.env.production? can't distinguish them. This flag is the only gate.
Rails.application.config.x.uat_db_reset_enabled =
  ActiveModel::Type::Boolean.new.cast(ENV["UAT_DB_RESET_ENABLED"])
