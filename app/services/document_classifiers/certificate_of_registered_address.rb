# frozen_string_literal: true

module DocumentClassifiers
  class CertificateOfRegisteredAddress < Base
    register handler: :certificate_of_registered_address

    def self.pattern
      /(certificate|confirmation)\s*(of\s*)?registered\s*address/i
    end
  end
end
