# frozen_string_literal: true

class ApplicantUsersController < ApplicationController
  expose(:applicant_user) { ApplicantUser.find(params[:id]) }

  def destroy
    authorize applicant_user
    applicant = applicant_user.applicant
    applicant_user.destroy!
    redirect_to applicant_path(applicant), notice: t("flash.applicant_users.destroy_success")
  end
end
