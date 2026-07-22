# frozen_string_literal: true

class ApplicantUserPolicy < ApplicationPolicy
  def destroy?
    psp_admin?
  end
end
