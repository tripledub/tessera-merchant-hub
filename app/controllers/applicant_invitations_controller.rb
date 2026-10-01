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
    @email_sent = deliver_invitation_email(invitation, @invitation_url)
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

  # Delivered synchronously so a failure can be surfaced on this same
  # response (a flash/notice pointing at the manual-copy fallback) rather
  # than failing silently in a background job the PSP admin never sees.
  def deliver_invitation_email(invitation, url)
    ApplicantInvitationMailer.invite(invitation, url).deliver_now
    true
  rescue StandardError => error
    Rails.error.report(error, handled: true, context: { invitation_id: invitation.id })
    false
  end
end
