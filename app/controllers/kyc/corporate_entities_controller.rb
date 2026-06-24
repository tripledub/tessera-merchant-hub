# frozen_string_literal: true

module Kyc
  class CorporateEntitiesController < ApplicationController
    expose(:entity) { Kyc::CorporateEntity.find(params[:id]) }

    def show
      authorize entity.applicant, :show?
    end
  end
end
