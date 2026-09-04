# frozen_string_literal: true

class ApplicantDomainPolicy < ApplicationPolicy
  def show?
    psp_role?
  end

  def new?
    psp_admin?
  end

  def create?
    psp_admin?
  end

  def destroy?
    psp_admin?
  end
end
