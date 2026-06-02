# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  def index?
    psp_admin? || merchant_admin?
  end

  def create?
    psp_admin? || merchant_admin?
  end

  def update?
    return true if psp_admin?
    return false unless merchant_admin?

    user.merchant_id == record.merchant_id
  end

  def destroy?
    psp_admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user.psp_admin?

      scope.where(merchant_id: user.merchant_id)
    end
  end
end
