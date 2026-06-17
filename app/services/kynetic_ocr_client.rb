# frozen_string_literal: true

class KyneticOcrClient
  class Error < StandardError; end

  BASE_URL = ENV.fetch("KYNETIC_OCR_URL", "http://localhost:8001")

  def self.process(customer_id:, document_key:)
    response = connection.post("/process", { customer_id: customer_id, document_key: document_key }.to_json)
    raise Error, "OCR service error: #{response.status}" unless response.success?

    JSON.parse(response.body)
  rescue Faraday::Error => e
    raise Error, e.message
  end

  def self.connection
    Faraday.new(BASE_URL) do |f|
      f.headers["Content-Type"] = "application/json"
      f.request :retry, max: 3, interval: 0.5, exceptions: [ Faraday::ServerError, Faraday::ConnectionFailed ]
    end
  end
end
