# frozen_string_literal: true

module Kyc
  class PolicyRequirement
    attr_reader :id, :rule, :outcome, :title, :guidance, :source, :parameters

    def initialize(id:, rule:, outcome:, title:, guidance:, source:, parameters:)
      @id = id
      @rule = rule
      @outcome = outcome
      @title = title
      @guidance = guidance
      @source = source
      @parameters = parameters
      freeze
    end
  end
end
