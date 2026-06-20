# frozen_string_literal: true

module DocumentClassifiers
  class CertificateOfAmendment < Base
    register handler: :certificate_of_amendment

    def self.pattern
      /certificate\s*(of\s*)?amendment/i
    end
  end
end
