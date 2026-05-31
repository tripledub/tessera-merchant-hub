# frozen_string_literal: true

require "faraday"
require "json"

class TesseraCoreClient
  class Error < StandardError; end
  class NotFoundError < Error; end
  class UnauthorizedError < Error; end
  class RefundError < Error; end
  class ServerError < Error; end

  def initialize(base_url: ENV.fetch("TESSERA_CORE_URL"), api_key: ENV.fetch("TESSERA_INTERNAL_API_KEY"))
    @connection = Faraday.new(url: base_url) do |f|
      f.request :json
      f.response :raise_error
      f.adapter Faraday.default_adapter
    end
    @api_key = api_key
  end

  def post_refund(shop_id:, payment_id:, amount:, currency:)
    response = post(
      "/v1/payments/#{payment_id}/refunds",
      { shop_id: shop_id, amount: amount, currency: currency }
    )
    parse(response)
  end

  def post_void(shop_id:, payment_id:)
    response = post(
      "/v1/payments/#{payment_id}/void",
      { shop_id: shop_id }
    )
    parse(response)
  end

  private

  def post(path, body)
    @connection.post(path, body, auth_headers)
  rescue Faraday::ResourceNotFound
    raise NotFoundError, "Resource not found at #{path}"
  rescue Faraday::UnauthorizedError
    raise UnauthorizedError, "Unauthorized — check TESSERA_INTERNAL_API_KEY"
  rescue Faraday::UnprocessableEntityError
    raise RefundError, "Unprocessable entity at #{path}"
  rescue Faraday::ServerError
    raise ServerError, "Server error from tessera-core at #{path}"
  end

  def auth_headers
    { "X-Internal-Api-Key" => @api_key }
  end

  def parse(response)
    JSON.parse(response.body)
  end
end
