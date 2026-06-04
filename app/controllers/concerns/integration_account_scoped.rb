# frozen_string_literal: true

module IntegrationAccountScoped
  extend ActiveSupport::Concern

  private

  def integration_account_id_for(shop)
    shop.integration_account_id
  end
end
