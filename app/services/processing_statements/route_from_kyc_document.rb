# frozen_string_literal: true

module ProcessingStatements
  class RouteFromKycDocument
    def self.call(document)
      document.with_lock do
        return document.processing_statement if document.processing_statement

        statement = ProcessingStatement.create!(
          applicant: document.applicant,
          status: :uploaded,
          file: document.file.blob
        )
        document.update!(processing_statement: statement)
        statement
      end
    end
  end
end
