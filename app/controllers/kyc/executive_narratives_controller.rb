# frozen_string_literal: true

class Kyc::ExecutiveNarrativesController < ApplicationController
  expose(:applicant) { Applicant.find(params[:applicant_id]) }

  def create
    authorize applicant, :show?

    begin
      narrative = Kyc::ExecutiveSummary::NarrativeGenerator.call(applicant, force: true)

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(
              "executive-narrative-content",
              partial: "applicants/tabs/summary/narrative_content",
              locals: { applicant: applicant, narrative: narrative }
            ),
            turbo_stream.append(
              "toast-container",
              partial: "shared/toast",
              locals: { message: t("flash.executive_narrative.generated"), type: :success }
            )
          ]
        end
        format.html { redirect_to applicant_path(applicant), notice: t("flash.executive_narrative.generated") }
      end
    rescue Kyc::ExecutiveSummary::NarrativeGenerator::Error => e
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.append(
            "toast-container",
            partial: "shared/toast",
            locals: { message: t("flash.executive_narrative.failed"), type: :error }
          )
        end
        format.html { redirect_to applicant_path(applicant), alert: t("flash.executive_narrative.failed") }
      end
    end
  end
end
