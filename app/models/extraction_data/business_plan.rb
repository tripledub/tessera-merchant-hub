# frozen_string_literal: true

module ExtractionData
  class BusinessPlan < Base
    register_as :business_plan

    attribute :company_name, :string
    attribute :summary, :string
    attribute :projected_revenue, :string
    attribute :projected_volume, :string
  end
end
