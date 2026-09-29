# frozen_string_literal: true

class OnboardingApplicationPolicy < ApplicationPolicy
  def show?
    confirmed_member?
  end

  def update?
    confirmed_member?
  end

  private

  def confirmed_member?
    user.confirmed? && user.applicant_id == record.applicant_id
  end
end
