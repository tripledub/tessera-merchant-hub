# frozen_string_literal: true

module Kyc
  class PolicyCataloguePolicy < ApplicationPolicy
    def index?
      psp_role?
    end
  end
end
