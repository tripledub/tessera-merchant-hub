class User < ApplicationRecord
  devise :database_authenticatable,
         :recoverable,
         :rememberable,
         :validatable,
         :trackable,
         :lockable

  enum :role, { psp_admin: 0, psp_support: 1, merchant_admin: 2, merchant_viewer: 3 }, default: :psp_admin

  validates :shop_id, presence: true, if: :merchant_role?

  def psp_role?
    psp_admin? || psp_support?
  end

  def merchant_role?
    merchant_admin? || merchant_viewer?
  end
end
