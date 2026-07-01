# frozen_string_literal: true

module Onboarding
  class DocumentCollectionService
    class << self
      def generate_checklist(session)
        new(session).generate_checklist
      end

      def received_documents(session)
        new(session).received_documents
      end

      def outstanding_items(session)
        new(session).outstanding_items
      end

      def all_received?(session)
        new(session).all_received?
      end

      def checklist_expects?(session, document_type)
        new(session).checklist_expects?(document_type)
      end
    end

    def initialize(session)
      @session = session
      @applicant = session.applicant
    end

    # Snapshots required documents once, at document_collection stage entry. Declared
    # data added or removed afterwards (e.g. a director added post-entry) is not
    # reflected — the checklist is a fixed contract, not a live view of declared data.
    def generate_checklist
      checklist = []
      checklist.concat(principal_items)
      checklist.concat(corporate_items)
      checklist.concat(nominee_items)
      @session.update!(document_checklist: checklist)
      checklist
    end

    def received_documents
      @received_documents ||= begin
        checklist = @session.document_checklist
        return [] if checklist.blank?

        documents = @applicant.kyc_documents.includes(:kyc_principal)

        checklist.map do |item|
          item.merge("received" => item_received?(item, documents))
        end
      end
    end

    def outstanding_items
      received_documents.reject { |item| item["received"] }
    end

    def all_received?
      checklist = @session.document_checklist
      return false if checklist.blank?

      outstanding_items.empty?
    end

    def checklist_expects?(document_type)
      checklist = @session.document_checklist
      return false if checklist.blank?

      checklist.any? { |item| item["document_types"].include?(document_type) }
    end

    private

    def principal_items
      principals = @applicant.kyc_principals.where(source: :applicant_declared)
      principals.flat_map do |principal|
        [
          {
            "category" => "identity",
            "subject" => principal.name,
            "document_types" => Kyc::DocumentCategory.types_for(:identity),
            "label" => "Proof of identity for #{principal.name}"
          },
          {
            "category" => "proof_of_address",
            "subject" => principal.name,
            "document_types" => Kyc::DocumentCategory.types_for(:proof_of_address),
            "label" => "Proof of address for #{principal.name}"
          }
        ]
      end
    end

    def corporate_items
      return [] unless @session.stage_data.key?("company_info")

      [
        {
          "category" => "corporate",
          "subject" => "company",
          "document_types" => %w[certificate_of_incorporation],
          "label" => "Certificate of incorporation"
        }
      ]
    end

    def nominee_items
      has_nominee = Kyc::OwnershipEdge
        .joins(:parent_entity)
        .where(parent_entity: { applicant: @applicant })
        .where(relationship_type: :nominee)
        .exists?

      return [] unless has_nominee

      [
        {
          "category" => "legal",
          "subject" => "company",
          "document_types" => %w[declaration_of_trust],
          "label" => "Declaration of trust"
        }
      ]
    end

    def item_received?(item, documents)
      category = item["category"]
      subject = item["subject"]
      doc_types = item["document_types"]

      if %w[identity proof_of_address].include?(category)
        documents.any? do |doc|
          doc_types.include?(doc.document_type) &&
            doc.kyc_principal&.name == subject
        end
      else
        documents.any? { |doc| doc_types.include?(doc.document_type) }
      end
    end
  end
end
