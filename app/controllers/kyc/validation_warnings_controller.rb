# frozen_string_literal: true

module Kyc
  class ValidationWarningsController < ApplicationController
    def update
      warning = ::Kyc::ValidationWarning.find(params[:id])
      authorize warning.applicant, :show?
      warning.update!(acknowledged: true)

      respond_to do |format|
        format.turbo_stream do
          presenter = Kyc::CompliancePresenter.new(warning.applicant, view_context)

          render turbo_stream: [
            turbo_stream.replace(
              "warning_#{warning.id}",
              partial: "applicants/tabs/compliance/warning_card",
              locals: { warning: warning, presenter: presenter }
            ),
            turbo_stream.update(
              "compliance_unacknowledged_count",
              partial: "applicants/tabs/compliance/unacknowledged_count",
              locals: { presenter: presenter }
            )
          ]
        end
        format.html { redirect_back fallback_location: applicant_path(warning.applicant, anchor: "compliance") }
      end
    end
  end
end
