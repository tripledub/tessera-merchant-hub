class User < ApplicationRecord
  devise :database_authenticatable,
         :recoverable,
         :rememberable,
         :validatable,
         :trackable,
         :lockable

  enum :role, { psp_admin: 0, psp_support: 1, merchant_admin: 2, merchant_viewer: 3 }, default: :psp_admin

  validates :merchant_id, presence: true, if: :merchant_role?

  def psp_role?
    psp_admin? || psp_support?
  end

  def merchant_role?
    merchant_admin? || merchant_viewer?
  end

  # Shop business keys this user may access. PSP roles are unscoped (nil →
  # "all"); merchant roles see every shop under their merchant.
  def accessible_shop_ids
    return nil if psp_role?

    Tessera::Shop.for_merchant(merchant_id).pluck(:shop_id)
  end
end
