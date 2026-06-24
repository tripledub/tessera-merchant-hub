# frozen_string_literal: true

module Kyc
  class CorporateEntitiesController < ApplicationController
    def show
      @entity = Kyc::CorporateEntity.find(params[:id])
      authorize @entity.applicant, :show?
    end
  end
end
