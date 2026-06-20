# frozen_string_literal: true

module DocumentClassifiers
  class CertificateOfDirectors < Base
    register handler: :certificate_of_directors

    def self.pattern
      /certificate\s*(of\s*)?directors?/i
    end
  end
end
