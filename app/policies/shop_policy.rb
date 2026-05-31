# frozen_string_literal: true

class ShopPolicy < ApplicationPolicy
  def index?
    psp_role?
  end

  def show?
    psp_role? || user.shop_id == record.id
  end

  def update?
    psp_admin?
  end

  alias edit? update?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope if user.psp_role?

      scope.where(id: user.shop_id)
    end
  end
end
