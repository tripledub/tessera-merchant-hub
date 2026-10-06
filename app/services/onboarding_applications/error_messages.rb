# frozen_string_literal: true

module OnboardingApplications
  # Human-readable messages for the errors currently on an application, in the
  # wording shown to applicants and staff for missing information.
  module ErrorMessages
    module_function

    def for(application)
      application.errors.objects.map do |error|
        next error.full_message if application.respond_to?(error.attribute)

        message = I18n.t(error.type, scope: "errors.messages", default: error.type.to_s.humanize)
        "#{error.attribute.to_s.humanize} #{message}"
      end
    end
  end
end
