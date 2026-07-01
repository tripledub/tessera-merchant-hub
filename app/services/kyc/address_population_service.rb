# frozen_string_literal: true

module Kyc
  class AddressPopulationService
    def self.call(document)
      new(document).call
    end

    def initialize(document)
      @document = document
    end

    def call
      return unless @document.complete?
      return unless Kyc::DocumentCategory.proof_of_address?(@document.document_type)
      return unless @document.kyc_principal.present?
      return unless @document.extracted_data.present?

      principal = @document.kyc_principal
      return if principal.address_line1.present?

      typed_data = @document.extraction_schema.new(@document.extracted_data)
      return unless typed_data.respond_to?(:structured_address)

      attrs = {
        address_line1: typed_data.structured_address[:line1],
        city:          typed_data.structured_address[:city],
        postcode:      typed_data.structured_address[:postcode],
        country:       typed_data.structured_address[:country]
      }.compact_blank

      return if attrs.empty?

      principal.update!(attrs)
    end
  end
end
