# frozen_string_literal: true

module DocumentClassifiers
  class DrivingLicence < Base
    register handler: :driving_licence

    def self.pattern
      /driving\s*(licence|license)/i
    end
  end
end
