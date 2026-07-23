# frozen_string_literal: true

class OnboardingSessionPolicy < ApplicationPolicy
  def index?
    psp_role?
  end

  def show?
    psp_role?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user.psp_role?

      scope.none
    end
  end
end
