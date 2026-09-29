# frozen_string_literal: true

class OnboardingApplicationPolicy < ApplicationPolicy
  def show?
    staff_reviewer? || confirmed_member?
  end

  def update?
    confirmed_member?
  end

  private

  def confirmed_member?
    user.is_a?(ApplicantUser) && user.confirmed? && user.applicant_id == record.applicant_id
  end

  def staff_reviewer?
    user.is_a?(User) && user.psp_role?
  end
end
