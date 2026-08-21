# frozen_string_literal: true

module Registry
  class Address < ApplicationRecord
    self.table_name = "registry_addresses"

    belongs_to :registry_profile, class_name: "Registry::Profile", inverse_of: :addresses

    enum :kind, { registered: "registered", trading: "trading" }, validate: true

    validates :line1, presence: true
  end
end
