# frozen_string_literal: true

module ProcessingStatementBroadcaster
  extend ActiveSupport::Concern

  private

  def broadcast_statement(statement)
    Turbo::StreamsChannel.broadcast_replace_to(
      "processing_statement_row_#{statement.id}",
      target: "processing_statement_status_#{statement.id}",
      partial: "processing_statements/statement_status",
      locals: { statement: statement }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      "processing_statement_#{statement.id}",
      target: "processing_statement_result_#{statement.id}",
      partial: "processing_statements/result_content",
      locals: { processing_statement: statement }
    )
  end
end
