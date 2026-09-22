# frozen_string_literal: true

# UAT/dev-only gate for synthetic test data (MH-310, MH-230): the fictional
# registry jurisdiction Utopia ("xu") and, later, generated specimen documents.
# Production never sets SYNTHETIC_DATA_ENABLED, so none of it is reachable there
# with no environment-specific code branch.
#
# Note: there's no Rails.env-based safety net on top of this: UAT and (once
# provisioned) production both run RAILS_ENV=production (see tessera-infra), so
# Rails.env.production? can't distinguish them. This flag is the only gate.
Rails.application.config.x.synthetic_data_enabled =
  ActiveModel::Type::Boolean.new.cast(ENV["SYNTHETIC_DATA_ENABLED"])
