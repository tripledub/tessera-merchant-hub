# frozen_string_literal: true

class ShopPolicy < ApplicationPolicy
  def index?
    psp_role?
  end

  def show?
    psp_role? || user.shop_id == record.shop_id
  end

  def update?
    psp_admin?
  end

  alias edit? update?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user.psp_role?

      scope.where(shop_id: user.shop_id)
    end
  end
end
