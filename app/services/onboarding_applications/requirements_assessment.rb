# frozen_string_literal: true

module OnboardingApplications
  class RequirementsAssessment
    Result = Data.define(:missing_information, :required_documents, :missing_documents, :readiness) do
      def complete?
        missing_information.empty? && missing_documents.empty?
      end
    end

    def self.for(application)
      new(application).call
    end

    def initialize(application)
      @application = application
    end

    def call
      return unless application.submitted?

      application.valid?(:submission)
      readiness = Kyc::Compliance::ReadinessAssessment.for(application.applicant)
      document_types = KycDocument.document_types.keys
      required_documents = readiness.all_results.flat_map(&:requirements).intersection(document_types)
      missing_documents = readiness.all_results.flat_map(&:missing).intersection(document_types)

      Result.new(
        missing_information: missing_information.freeze,
        required_documents: required_documents.uniq.freeze,
        missing_documents: missing_documents.uniq.freeze,
        readiness: readiness
      )
    end

    private

    attr_reader :application

    def missing_information
      application.errors.objects.map do |error|
        next error.full_message if application.respond_to?(error.attribute)

        message = I18n.t(error.type, scope: "errors.messages", default: error.type.to_s.humanize)
        "#{error.attribute.to_s.humanize} #{message}"
      end
    end
  end
end
