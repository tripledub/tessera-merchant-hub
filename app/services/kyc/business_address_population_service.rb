# frozen_string_literal: true

module Kyc
  class BusinessAddressPopulationService
    def self.call(document)
      new(document).call
    end

    def initialize(document)
      @document = document
    end

    def call
      return unless @document.complete?
      return unless Kyc::DocumentCategory.proof_of_business_address?(@document.document_type)
      return unless @document.extracted_data.present?
      return if @document.applicant.primary_business_address.present?

      typed_data = @document.extraction_schema.new(@document.extracted_data)
      return unless typed_data.is_a?(ExtractionData::Concerns::BusinessAddressProviding)

      attrs = typed_data.structured_address.compact_blank
      return unless %i[line1 city country].all? { |k| attrs[k].present? }

      @document.applicant.addresses.create!(
        type: "Address::Business",
        primary: true,
        line1:    attrs[:line1],
        city:     attrs[:city],
        postcode: attrs[:postcode],
        country:  attrs[:country]
      )
    rescue ActiveRecord::RecordInvalid => e
      raise unless e.record.errors.of_kind?(:primary, :taken)
    end
  end
end
