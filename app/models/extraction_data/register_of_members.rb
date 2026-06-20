# frozen_string_literal: true

module ExtractionData
  class RegisterOfMembers < Base
    register_as :register_of_members

    attribute :company_name, :string
    attribute :members, :string

    validates :company_name, presence: true
  end
end
