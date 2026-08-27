# frozen_string_literal: true

class ImportProcessingStatementJob < ApplicationJob
  include ProcessingStatementBroadcaster

  queue_as :default

  def perform(processing_statement_id, mapping)
    statement = ProcessingStatement.find(processing_statement_id)
    Statements::Importer.new(statement, mapping).call
    broadcast_statement(statement.reload)
  end
end
