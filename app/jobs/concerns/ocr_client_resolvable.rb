# frozen_string_literal: true

module OcrClientResolvable
  extend ActiveSupport::Concern

  private

  def ocr_client(document)
    if !Rails.env.production? && ENV["CLAUDE_OCR"].present?
      ClaudeOcrAdapter.process(document: document)
    else
      KyneticOcrClient.process(
        customer_id: document.applicant_id,
        document_key: document.file.key
      )
    end
  end
end
