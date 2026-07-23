# frozen_string_literal: true

class TranscriptsController < ApplicationController
  def index
    authorize OnboardingSession
    scope = policy_scope(OnboardingSession)
    filtered = Transcripts::IndexQuery.new(scope, filter_params).call
    @pagy, @sessions = pagy(:offset, filtered)
    @applicants = Applicant.where(id: scope.select(:applicant_id)).order(:name)
  end

  def show
    authorize OnboardingSession, :show?
    @session = policy_scope(OnboardingSession)
      .includes(:applicant, :onboarding_messages)
      .find(params[:id])
  end

  private

  def filter_params
    params.permit(:applicant_id, :status, :current_stage, :date_from, :date_to)
  end
end
