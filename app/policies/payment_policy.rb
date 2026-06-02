# frozen_string_literal: true

class PaymentPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    psp_role? || own_shop?(record)
  end

  def refund?
    (psp_role? || merchant_admin?) && (psp_role? || own_shop?(record))
  end

  def void?
    refund?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope if user.psp_role?

      scope.where(shop_id: user.accessible_shop_ids)
    end
  end
end
