# frozen_string_literal: true

class Address < ApplicationRecord
  belongs_to :addressable, polymorphic: true

  validates :line1, :city, :country, presence: true
  validates :primary, uniqueness: {
    scope: [ :addressable_type, :addressable_id, :type ],
    conditions: -> { where(primary: true) },
    message: "address already exists for this addressable and type"
  }, if: :primary?
end
