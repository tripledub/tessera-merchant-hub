# frozen_string_literal: true

module Registry
  class Client
    def fetch(company_number:)
      raise NotImplementedError, "#{self.class}#fetch must be implemented"
    end
  end
end
