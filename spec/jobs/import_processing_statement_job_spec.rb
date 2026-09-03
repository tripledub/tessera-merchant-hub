# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImportProcessingStatementJob, type: :job do
  let(:csv) do
    <<~CSV
      Txn Date,Value,Currency,Result
      2026-04-01,100.00,GBP,approved
      2026-04-15,50.00,GBP,declined
    CSV
  end

  let(:statement) do
    s = create(:processing_statement, status: :mapped, column_mapping: mapping)
    s.file.attach(io: StringIO.new(csv), filename: "statement.csv", content_type: "text/csv")
    s.save!(validate: false)
    s
  end

  let(:mapping) { { "date" => "Txn Date", "amount" => "Value", "currency" => "Currency", "outcome" => "Result" } }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform" do
    it "imports the statement and marks it processed" do
      described_class.new.perform(statement.id, mapping)

      statement.reload
      expect(statement.status).to eq("processed")
      expect(statement.metrics["overall"]["total_volume"]).to eq({ "GBP" => "150.0" })
    end

    it "broadcasts updated index and detail replacements" do
      described_class.new.perform(statement.id, mapping)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        "processing_statement_row_#{statement.id}",
        target: "processing_statement_#{statement.id}",
        partial: "processing_statements/statement",
        locals: { statement: statement, mapping_allowed: false, removal_allowed: false }
      )
      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        "processing_statement_#{statement.id}",
        target: "processing_statement_#{statement.id}",
        partial: "processing_statements/result",
        locals: { processing_statement: statement, mapping_allowed: false, removal_allowed: false }
      )
    end

    it "marks the statement as error without raising when the row limit is exceeded" do
      stub_const("ProcessingStatement::MAX_ROWS", 1)

      described_class.new.perform(statement.id, mapping)

      statement.reload
      expect(statement.status).to eq("error")
      expect(statement.error_message).to match(/exceeds/i)
      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        "processing_statement_row_#{statement.id}", hash_including(target: "processing_statement_#{statement.id}")
      )
      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        "processing_statement_#{statement.id}", hash_including(target: "processing_statement_#{statement.id}")
      )
    end

    it "finishes quietly when the errored statement is removed before broadcasting" do
      importer = instance_double(Statements::Importer)
      allow(Statements::Importer).to receive(:new).with(statement, mapping).and_return(importer)
      allow(importer).to receive(:call) do
        statement.update!(status: :error, error_message: "Invalid row")
        statement.destroy!
      end

      expect { described_class.new.perform(statement.id, mapping) }.not_to raise_error
      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
    end
  end
end
