# frozen_string_literal: true

class PaymentPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    psp_role? || own_shop?(record)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope if user.psp_role?

      scope.select { |payment| payment.shop_id == user.shop_id }
    end
  end
end
