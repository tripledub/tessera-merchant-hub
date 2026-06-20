# frozen_string_literal: true

module ExtractionData
  class MemorandumOfAssociation < Base
    register_as :memorandum_of_association

    attribute :company_name, :string
    attribute :objectives, :string
    attribute :authorized_share_capital, :string
    attribute :subscribers, :string

    validates :company_name, presence: true
  end
end
