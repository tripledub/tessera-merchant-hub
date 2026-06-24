class User < ApplicationRecord
  devise :database_authenticatable,
         :recoverable,
         :rememberable,
         :validatable,
         :trackable,
         :lockable,
         :timeoutable

  enum :role, { psp_admin: 0, psp_support: 1, merchant_admin: 2, merchant_viewer: 3 }, default: :merchant_viewer

  scope :active,      -> { where(deactivated_at: nil) }
  scope :deactivated, -> { where.not(deactivated_at: nil) }

  validates :merchant_id, presence: true, if: :merchant_role?

  def psp_role?
    psp_admin? || psp_support?
  end

  def merchant_role?
    merchant_admin? || merchant_viewer?
  end

  def deactivated?
    deactivated_at.present?
  end

  # Devise hook — prevents sign-in for deactivated accounts regardless of password
  def active_for_authentication?
    super && !deactivated?
  end

  def inactive_message
    deactivated? ? :deactivated : super
  end

  # Shop business keys this user may access. PSP roles are unscoped (nil →
  # "all"); merchant roles see every shop under their merchant.
  def accessible_shop_ids
    return nil if psp_role?

    Tessera::Shop.for_merchant(merchant_id).pluck(:shop_id)
  end
end
