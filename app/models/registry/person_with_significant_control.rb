# frozen_string_literal: true

module Registry
  class PersonWithSignificantControl < ApplicationRecord
    self.table_name = "registry_people_with_significant_control"

    belongs_to :registry_profile, class_name: "Registry::Profile", inverse_of: :people_with_significant_control

    validates :name, presence: true
    validates :kind, presence: true
  end
end
