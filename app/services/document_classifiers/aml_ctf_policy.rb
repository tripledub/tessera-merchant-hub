# frozen_string_literal: true

module DocumentClassifiers
  class AmlCtfPolicy < Base
    register handler: :aml_ctf_policy

    def self.pattern
      /anti.money\s*laundering|aml.*(policy|counter.terrorism|ctf\s*policy)/i
    end
  end
end
