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

  def create_merchant(name:, company_name: nil, country: nil)
    body = compact(name: name, company_name: company_name, country: country)
    parse(post("/v1/merchants", body))
  end

  def create_shop(merchant_id:, name:, country:, notification_url: nil)
    body = compact(name: name, country: country, notification_url: notification_url)
    parse(post("/v1/merchants/#{merchant_id}/shops", body))
  end

  def update_shop(shop_id:, **attrs)
    parse(patch("/v1/shops/#{shop_id}", compact(attrs)))
  end

  def create_credential(shop_id:)
    parse(post("/v1/shops/#{shop_id}/credentials", {}))
  end

  def list_credentials(shop_id:)
    parse(get("/v1/shops/#{shop_id}/credentials"))
  end

  def revoke_credential(shop_id:, id:)
    parse(delete("/v1/shops/#{shop_id}/credentials/#{id}"))
  end

  def configure_credential(shop_id:, id:, ip_allowlist: nil, signing_required: nil)
    body = compact(ip_allowlist: ip_allowlist, signing_required: signing_required)
    parse(patch("/v1/shops/#{shop_id}/credentials/#{id}", body))
  end

  private

  def post(path, body)
    @connection.post(path, body, auth_headers)
  rescue Faraday::Error => e
    raise translate_error(e, path)
  end

  def get(path)
    @connection.get(path, nil, auth_headers)
  rescue Faraday::Error => e
    raise translate_error(e, path)
  end

  def patch(path, body)
    @connection.patch(path, body, auth_headers)
  rescue Faraday::Error => e
    raise translate_error(e, path)
  end

  def delete(path)
    @connection.delete(path, nil, auth_headers)
  rescue Faraday::Error => e
    raise translate_error(e, path)
  end

  def translate_error(error, path)
    case error
    when Faraday::ResourceNotFound
      NotFoundError.new("Resource not found at #{path}")
    when Faraday::UnauthorizedError
      UnauthorizedError.new("Unauthorized — check TESSERA_INTERNAL_API_KEY")
    when Faraday::UnprocessableEntityError
      RefundError.new("Unprocessable entity at #{path}")
    when Faraday::ServerError
      ServerError.new("Server error from tessera-core at #{path}")
    else
      Error.new("Request to #{path} failed: #{error.message}")
    end
  end

  def compact(hash)
    hash.reject { |_, value| value.nil? }
  end

  def auth_headers
    { "X-Internal-Api-Key" => @api_key }
  end

  def parse(response)
    JSON.parse(response.body)
  end
end
