# frozen_string_literal: true

module DocumentClassifiers
  class RegisterOfMembers < Base
    register handler: :register_of_members

    def self.pattern
      /register\s*(of\s*)?members?(\s*and\s*share\s*ledger)?/i
    end
  end
end
