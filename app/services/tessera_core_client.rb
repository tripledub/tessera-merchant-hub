# frozen_string_literal: true

require "faraday"
require "json"
require "uri"

class TesseraCoreClient
  class Error < StandardError; end
  class NotFoundError < Error; end
  class UnauthorizedError < Error; end
  class RefundError < Error; end
  class ServerError < Error; end

  INTERNAL_PREFIX = "/internal/integration_accounts"

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

  def create_integration_account(
    merchant_hub_merchant_id:,
    merchant_hub_shop_id:,
    secret_key:,
    id: nil,
    acquirer_key: nil,
    credentials_ref: nil
  )
    body = compact(
      id: id,
      secret_key: secret_key,
      merchant_hub_merchant_id: merchant_hub_merchant_id,
      merchant_hub_shop_id: merchant_hub_shop_id,
      acquirer_key: acquirer_key,
      credentials_ref: credentials_ref
    )
    parse(post(INTERNAL_PREFIX, body))
  end

  def get_integration_account(integration_account_id:)
    parse(get("#{INTERNAL_PREFIX}/#{integration_account_id}"))
  end

  def lookup_integration_account(merchant_hub_shop_id:)
    parse(
      get(
        "#{INTERNAL_PREFIX}/lookup?merchant_hub_shop_id=#{URI.encode_www_form_component(merchant_hub_shop_id)}"
      )
    )
  end

  def update_integration_account(integration_account_id:, **attrs)
    body = compact(
      merchant_hub_merchant_id: attrs[:merchant_hub_merchant_id],
      merchant_hub_shop_id: attrs[:merchant_hub_shop_id],
      acquirer_key: attrs[:acquirer_key],
      credentials_ref: attrs[:credentials_ref]
    )
    parse(patch("#{INTERNAL_PREFIX}/#{integration_account_id}", body))
  end

  def create_acquirer_config(integration_account_id:, **attrs)
    body = compact(
      id: attrs[:id],
      acquirer_key: attrs[:acquirer_key],
      credentials_ref: attrs[:credentials_ref],
      enabled: attrs[:enabled]
    )
    parse(post("#{INTERNAL_PREFIX}/#{integration_account_id}/acquirer_configs", body))
  end

  def update_acquirer_config(integration_account_id:, config_id:, **attrs)
    body = compact(
      acquirer_key: attrs[:acquirer_key],
      credentials_ref: attrs[:credentials_ref],
      enabled: attrs[:enabled]
    )
    parse(patch("#{INTERNAL_PREFIX}/#{integration_account_id}/acquirer_configs/#{config_id}", body))
  end

  def create_credential(integration_account_id:, ip_allowlist: nil, signing_required: nil)
    body = compact(ip_allowlist: ip_allowlist, signing_required: signing_required)
    normalize_credential(parse(post("#{INTERNAL_PREFIX}/#{integration_account_id}/credentials", body)))
  end

  def list_credentials(integration_account_id:)
    body = parse(get("#{INTERNAL_PREFIX}/#{integration_account_id}/credentials"))
    credentials = body.fetch("credentials", body)
    Array(credentials).map { |item| normalize_credential_metadata(item) }
  end

  def revoke_credential(integration_account_id:, credential_id:)
    normalize_credential_metadata(
      parse(delete("#{INTERNAL_PREFIX}/#{integration_account_id}/credentials/#{credential_id}"))
    )
  end

  def configure_credential(integration_account_id:, credential_id:, ip_allowlist: nil, signing_required: nil)
    body = compact(ip_allowlist: ip_allowlist, signing_required: signing_required)
    normalize_credential_metadata(
      parse(patch("#{INTERNAL_PREFIX}/#{integration_account_id}/credentials/#{credential_id}", body))
    )
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

  def normalize_credential(payload)
    normalize_credential_metadata(payload).merge(
      "pk" => payload["api_key"] || payload["pk"],
      "sk" => payload["secret_key"] || payload["sk"],
      "signing_secret" => payload["signing_secret"]
    )
  end

  def normalize_credential_metadata(payload)
    payload.merge(
      "pk" => payload["api_key"] || payload["pk"],
      "created" => payload["created_at"] || payload["created"],
      "last_used" => payload["last_used_at"] || payload["last_used"]
    )
  end
end
