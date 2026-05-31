class Shop < ApplicationRecord
  validates :shop_id, presence: true, uniqueness: true
  validates :name, presence: true
  validates :notification_url, format: { with: %r{\Ahttps://[^\s]+\z}i, message: "must be an HTTPS URL" },
                                allow_blank: true

  scope :for_user, ->(user) { user.psp_role? ? all : where(shop_id: user.shop_id) }
end
