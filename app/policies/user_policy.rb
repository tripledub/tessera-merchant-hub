# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  def index?             = psp_admin? || merchant_admin?
  def admin_index?       = psp_admin?
  def admin_invite?      = psp_admin?
  def invite?            = psp_admin? || merchant_admin?
  # Role-level gate (no record needed): can this user type deactivate anyone?
  def deactivate_role?   = psp_admin? || merchant_admin?
  def deactivate?        = (psp_admin? || (merchant_admin? && own_merchant?)) && record != user
  def unlock?      = psp_admin?
  def update_role? = psp_admin?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user.psp_admin?
      return scope.where(merchant_id: user.merchant_id) if user.merchant_admin?

      scope.none
    end
  end

  private

  def own_merchant?
    user.merchant_id.present? && user.merchant_id == record.merchant_id
  end
end
