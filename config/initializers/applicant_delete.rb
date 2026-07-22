# frozen_string_literal: true

# UAT-only gate for admin Applicant deletion (MH-170). Production never sets
# APPLICANT_DELETE_ENABLED, so the destroy path stays inert there with no
# environment-specific code branch.
Rails.application.config.x.applicant_delete_enabled =
  ActiveModel::Type::Boolean.new.cast(ENV["APPLICANT_DELETE_ENABLED"])
