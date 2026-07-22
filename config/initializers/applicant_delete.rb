# frozen_string_literal: true

# UAT-only gate for admin Applicant deletion (MH-170). Production never sets
# APPLICANT_DELETE_ENABLED, so the destroy path stays inert there with no
# environment-specific code branch.
#
# Note: there's no Rails.env-based safety net on top of this — UAT and (once
# provisioned) production both run RAILS_ENV=production (see tessera-infra),
# so Rails.env.production? can't distinguish them. This flag is the only gate.
Rails.application.config.x.applicant_delete_enabled =
  ActiveModel::Type::Boolean.new.cast(ENV["APPLICANT_DELETE_ENABLED"])
