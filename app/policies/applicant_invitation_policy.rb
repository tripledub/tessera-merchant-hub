# frozen_string_literal: true

class ApplicantInvitationPolicy < ApplicationPolicy
  def new?
    psp_admin?
  end

  def create?
    psp_admin?
  end
end
