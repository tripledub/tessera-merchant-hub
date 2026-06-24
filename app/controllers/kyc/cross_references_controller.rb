# frozen_string_literal: true

module Kyc
  class CrossReferencesController < ApplicationController
    expose(:corporate_entity) { Kyc::CorporateEntity.find(params[:corporate_entity_id]) }

    def create
      authorize corporate_entity.applicant, :show?
      result = Kyc::CrossReferenceService.call(corporate_entity)

      message, type = if result.success?
        [ "Cross-reference complete for #{corporate_entity.name}", :success ]
      else
        failed_docs = result.inference_errors.map { |e| e[:document] }.join(", ")
        [ "Cross-reference finished with errors (#{failed_docs})", :error ]
      end

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.append(
            "toast-container",
            partial: "shared/toast",
            locals: { message: message, type: type }
          )
        end
        format.html { redirect_to kyc_corporate_entity_path(corporate_entity) }
      end
    end
  end
end
