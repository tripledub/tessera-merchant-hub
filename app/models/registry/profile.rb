# frozen_string_literal: true

module Registry
  class Profile < ApplicationRecord
    self.table_name = "registry_profiles"

    belongs_to :applicant

    has_many :directors, class_name: "Registry::Director", dependent: :destroy, inverse_of: :registry_profile
    has_many :addresses, class_name: "Registry::Address", dependent: :destroy, inverse_of: :registry_profile

    validates :jurisdiction, presence: true
    validates :company_number, presence: true
    validates :company_name, presence: true
    validates :fetched_at, presence: true
  end
end
