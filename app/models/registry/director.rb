# frozen_string_literal: true

module Registry
  class Director < ApplicationRecord
    self.table_name = "registry_directors"

    belongs_to :registry_profile, class_name: "Registry::Profile", inverse_of: :directors

    validates :name, presence: true
    validates :role, presence: true
  end
end
