# frozen_string_literal: true

module DocumentClassifiers
  class CertificateOfShareholders < Base
    register handler: :certificate_of_shareholders

    def self.pattern
      /certificate\s*(of\s*)?shareholders?/i
    end
  end
end
