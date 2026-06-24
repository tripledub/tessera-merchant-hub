# frozen_string_literal: true

module Kyc
  class CorporateEntitiesController < ApplicationController
    expose(:entity) { Kyc::CorporateEntity.find(params[:id]) }

    def show
      authorize entity.applicant, :show?
    end

    def cross_reference
      authorize entity.applicant, :show?
      Kyc::CrossReferenceService.call(entity)

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.append(
            "toast-container",
            partial: "shared/toast",
            locals: { message: "Cross-reference complete for #{entity.name}", type: :success }
          )
        end
        format.html { redirect_to kyc_corporate_entity_path(entity) }
      end
    end
  end
end
