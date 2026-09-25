# frozen_string_literal: true

module Kyc
  class PoliciesController < ApplicationController
    def index
      authorize :policy_catalogue, policy_class: Kyc::PolicyCataloguePolicy
      @policy_catalogue = Kyc::PolicyCataloguePresenter.new(Kyc::PolicyRegistry.instance, view_context)
    end
  end
end
