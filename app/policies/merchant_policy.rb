# frozen_string_literal: true

# Authorization policy for MerchantHub-owned Merchant records (ADR-007).
# new?/create? are used with Tessera::Merchant (headless, for onboarding).
# index?/show?/edit?/update? are used with Merchant AR instances.
class MerchantPolicy < ApplicationPolicy
  def new?
    psp_admin?
  end

  def create?
    psp_admin?
  end

  def index?
    psp_role?
  end

  def show?
    psp_role? || (merchant_admin? && own_merchant?)
  end

  def edit?
    psp_admin? || (merchant_admin? && own_merchant?)
  end

  def update?
    edit?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all                                   if user.psp_role?
      return scope.where(merchant_id: user.merchant_id) if user.merchant_admin?

      scope.none
    end
  end

  private

  def own_merchant?
    user.merchant_id.present? && user.merchant_id == record.merchant_id
  end
end
