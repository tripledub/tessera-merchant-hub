# frozen_string_literal: true

module OnboardingApplications
  class RequirementsAssessment
    Result = Data.define(:missing_information, :required_documents, :missing_documents, :readiness) do
      def complete?
        missing_information.empty? && missing_documents.empty?
      end
    end

    DocumentRequirements = Data.define(:required, :missing, :readiness)

    def self.for(application)
      new(application).call
    end

    # Documents the shared KYC policy asks for, and which of them are still
    # missing. Independent of submission, so it also serves draft applications.
    def self.document_requirements(applicant)
      readiness = Kyc::Compliance::ReadinessAssessment.for(applicant)
      document_types = KycDocument.document_types.keys

      DocumentRequirements.new(
        required: readiness.all_results.flat_map(&:requirements).intersection(document_types).uniq.freeze,
        missing: readiness.all_results.flat_map(&:missing).intersection(document_types).uniq.freeze,
        readiness: readiness
      )
    end

    def initialize(application)
      @application = application
    end

    def call
      return unless application.submitted?

      application.valid?(:submission)
      documents = self.class.document_requirements(application.applicant)

      Result.new(
        missing_information: ErrorMessages.for(application).freeze,
        required_documents: documents.required,
        missing_documents: documents.missing,
        readiness: documents.readiness
      )
    end

    private

    attr_reader :application
  end
end
