# frozen_string_literal: true

class ApplicantPolicy < ApplicationPolicy
  def index?
    psp_role?
  end

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

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user.psp_role?

      scope.none
    end
  end
end
