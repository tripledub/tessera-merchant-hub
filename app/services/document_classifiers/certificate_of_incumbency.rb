# frozen_string_literal: true

module DocumentClassifiers
  class CertificateOfIncumbency < Base
    register handler: :certificate_of_incumbency

    def self.pattern
      /certificate\s*(of\s*)?incumbency/i
    end
  end
end
