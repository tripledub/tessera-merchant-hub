# frozen_string_literal: true

module TesseraCoreClientDependency
  extend ActiveSupport::Concern

  private

  def tessera_core_client
    @tessera_core_client ||= TesseraCoreClient.new
  end
end
