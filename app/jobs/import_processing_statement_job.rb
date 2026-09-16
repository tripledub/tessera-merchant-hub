# frozen_string_literal: true

class ImportProcessingStatementJob < ApplicationJob
  include ProcessingStatementBroadcaster

  queue_as :default

  def perform(processing_statement_id, mapping)
    statement = ProcessingStatement.find_by(id: processing_statement_id)
    return unless statement

    Statements::Importer.new(statement, mapping).call
    refreshed_statement = ProcessingStatement.find_by(id: processing_statement_id)
    broadcast_statement(refreshed_statement) if refreshed_statement
  end
end
