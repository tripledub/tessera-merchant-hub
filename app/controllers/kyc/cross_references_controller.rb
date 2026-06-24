# frozen_string_literal: true

module Kyc
  class CrossReferencesController < ApplicationController
    expose(:corporate_entity) { Kyc::CorporateEntity.find(params[:corporate_entity_id]) }

    def create
      authorize corporate_entity.applicant, :show?
      Kyc::CrossReferenceService.call(corporate_entity)

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.append(
            "toast-container",
            partial: "shared/toast",
            locals: { message: "Cross-reference complete for #{corporate_entity.name}", type: :success }
          )
        end
        format.html { redirect_to kyc_corporate_entity_path(corporate_entity) }
      end
    end
  end
end
