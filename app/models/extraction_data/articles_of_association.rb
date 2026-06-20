# frozen_string_literal: true

module ExtractionData
  class ArticlesOfAssociation < Base
    register_as :articles_of_association

    attribute :company_name, :string
    attribute :amendment_date, :date

    validates :company_name, presence: true
  end
end
