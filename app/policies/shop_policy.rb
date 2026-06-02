# frozen_string_literal: true

class ShopPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    psp_role? || own_merchant?(record)
  end

  def create?
    psp_admin? || merchant_admin?
  end

  alias new? create?

  def update?
    psp_admin? || (merchant_admin? && own_merchant?(record))
  end

  alias edit? update?

  def generate_credential?
    update?
  end

  def revoke_credential?
    update?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user.psp_role?

      scope.for_merchant(user.merchant_id)
    end
  end

  private

  def own_merchant?(record)
    user.merchant_id.present? && user.merchant_id == record.merchant_id
  end
end
