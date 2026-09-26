# frozen_string_literal: true

class ApplicantInvitationsController < ApplicationController
  expose(:applicant) { Applicant.find(params[:applicant_id]) }
  expose(:applicant_invitation) do
    ApplicantInvitation.new(applicant: applicant, email: applicant.contact_email, invited_by: current_user)
  end

  def new
    authorize applicant_invitation
  end

  def create
    authorize applicant_invitation
    invitation, token = ApplicantInvitation.issue!(
      applicant: applicant,
      email: applicant_invitation_params[:email],
      invited_by: current_user
    )
    @invitation_url = portal_invitation_url(token: token)
    render :create, locals: { invitation: invitation }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    applicant_invitation.assign_attributes(email: applicant_invitation_params[:email])
    error.record.errors.each { |record_error| applicant_invitation.errors.import(record_error) }
    render :new, status: :unprocessable_content
  end

  private

  def applicant_invitation_params
    params.require(:applicant_invitation).permit(:email)
  end
end
