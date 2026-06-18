# frozen_string_literal: true

class KycPrincipalPolicy < ApplicationPolicy
  def show?
    psp_role?
  end

  def new?
    psp_admin?
  end

  def create?
    psp_admin?
  end

  def edit?
    psp_admin?
  end

  def update?
    psp_admin?
  end

  def destroy?
    psp_admin?
  end
end
