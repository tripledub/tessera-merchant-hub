# frozen_string_literal: true

module Applicants
  class Deletion
    def self.call(applicant) = new(applicant).call

    def initialize(applicant)
      @applicant = applicant
    end

    def call
      if @applicant.applicant_users.any?
        @applicant.errors.add(:base, "Cannot delete an applicant with an active portal user account")
        return @applicant
      end

      @applicant.destroy!
      @applicant
    end
  end
end
