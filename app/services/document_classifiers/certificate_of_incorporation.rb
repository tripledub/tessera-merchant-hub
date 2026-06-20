# frozen_string_literal: true

module DocumentClassifiers
  class CertificateOfIncorporation < Base
    register handler: :certificate_of_incorporation

    def self.pattern
      /certificate\s*(of\s*)?incorporation/i
    end
  end
end
