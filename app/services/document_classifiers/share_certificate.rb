# frozen_string_literal: true

module DocumentClassifiers
  class ShareCertificate < Base
    register handler: :share_certificate

    def self.pattern
      /share\s*certificate/i
    end
  end
end
