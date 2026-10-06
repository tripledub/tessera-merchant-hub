# frozen_string_literal: true

# MH-389: after submission, compare what the applicant told us with the registry. Never
# blocks or fails the submission; differences become conflicts for staff.
class RegistryRecheckJob < ApplicationJob
  queue_as :default

  def perform(applicant_id)
    applicant = Applicant.find_by(id: applicant_id)
    return unless applicant

    Provenance::RegistryRecheck.call(applicant)
  end
end
