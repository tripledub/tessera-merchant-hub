# frozen_string_literal: true

module DocumentClassifiers
  class Passport < Base
    register handler: :passport

    def self.pattern
      /passport/i
    end
  end
end
