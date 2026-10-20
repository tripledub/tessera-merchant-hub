# frozen_string_literal: true

module OnboardingApplications
  class SaveCompanyDetails
    def self.call(application:, attributes:)
      previous = Provenance::CompanyFields::FIELDS.index_with { |field| application.applicant.public_send(field) }

      saved = SaveStepDetails.call(application: application, step: "company", attributes: attributes)
      # Read the applicant again: saving locks (and so reloads) the application.
      record_edits(application.applicant, previous) if saved
      saved
    end

    # MH-389: the form saved the applicant's answers; note where they came from and flag
    # any change to a value a higher-ranked source (the registry) had supplied.
    def self.record_edits(applicant, previous)
      Provenance::CompanyFields::FIELDS.each do |field|
        Provenance::CompanyFields.record_applicant_edit!(applicant: applicant, field: field,
                                                         previous_value: previous.fetch(field))
      end
    end
    private_class_method :record_edits
  end
end
