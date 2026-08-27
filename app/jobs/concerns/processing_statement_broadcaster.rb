# frozen_string_literal: true

module ProcessingStatementBroadcaster
  extend ActiveSupport::Concern

  private

  def broadcast_statement(statement)
    Turbo::StreamsChannel.broadcast_replace_to(
      "processing_statement_#{statement.id}",
      target: "processing_statement_#{statement.id}",
      partial: "processing_statements/result",
      locals: { processing_statement: statement }
    )
  end
end
