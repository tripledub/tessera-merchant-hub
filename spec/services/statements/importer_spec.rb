# frozen_string_literal: true

require "rails_helper"

RSpec.describe Statements::Importer do
  let(:csv) do
    <<~CSV
      Txn Date,Value,Currency,Result
      2026-04-01,100.00,GBP,approved
      2026-04-15,50.00,GBP,declined
      2026-05-02,25.00,GBP,chargeback
    CSV
  end

  let(:statement) do
    s = build(:processing_statement)
    s.file.attach(io: StringIO.new(csv), filename: "statement.csv", content_type: "text/csv")
    s.save!(validate: false)
    s
  end

  let(:mapping) { { "date" => "Txn Date", "amount" => "Value", "currency" => "Currency", "outcome" => "Result" } }

  describe "#call" do
    # Mirrors production: the controller writes column_mapping to the
    # statement before enqueueing the job. Importer treats a mismatch
    # between this and the statement's current column_mapping as a stale,
    # superseded job (see the dedicated context below).
    before { statement.update!(column_mapping: mapping) }

    it "computes metrics from the mapped columns and persists them as processed" do
      described_class.new(statement, mapping).call

      statement.reload
      expect(statement.status).to eq("processed")
      expect(statement.column_mapping).to eq(mapping)
      expect(statement.row_count).to eq(3)
      expect(statement.metrics["overall"]["total_volume"]).to eq({ "GBP" => "175.0" })
      expect(statement.metrics["by_month"].keys).to eq(%w[2026-04 2026-05])
    end

    context "when the transaction table is followed by a summary footer" do
      let(:csv) do
        <<~CSV
          Txn Date,Value,Currency,Result
          2026-04-01,100.00,GBP,approved

          SUMMARY,,,
          Total transaction count,1,,
          Total volume,100.00,GBP,
        CSV
      end

      it "imports the transactions and ignores the blank separator and summary block" do
        described_class.new(statement, mapping).call

        statement.reload
        expect(statement.status).to eq("processed")
        expect(statement.row_count).to eq(1)
        expect(statement.metrics["overall"]["total_volume"]).to eq({ "GBP" => "100.0" })
      end
    end

    context "when a non-summary row contains malformed transaction data" do
      let(:csv) do
        <<~CSV
          Txn Date,Value,Currency,Result
          Notes,,,
        CSV
      end

      it "fails rather than silently discarding the row" do
        described_class.new(statement, mapping).call

        statement.reload
        expect(statement.status).to eq("error")
        expect(statement.error_message).to eq(
          'Row 2, field "date", column "Txn Date", value "Notes": invalid date'
        )
      end
    end

    context "when a populated transaction row begins with the summary marker" do
      let(:csv) do
        <<~CSV
          Txn Date,Value,Currency,Result
          SUMMARY,100.00,GBP,approved
        CSV
      end

      it "validates the row instead of treating it as a footer" do
        described_class.new(statement, mapping).call

        statement.reload
        expect(statement.status).to eq("error")
        expect(statement.error_message).to include('value "SUMMARY": invalid date')
      end
    end

    context "when a required field is not mapped" do
      before { statement.update!(column_mapping: { "date" => "Txn Date" }) }

      it "marks the statement as error without raising" do
        described_class.new(statement, { "date" => "Txn Date" }).call

        statement.reload
        expect(statement.status).to eq("error")
        expect(statement.error_message).to be_present
      end
    end

    context "when a row has an unparseable amount or date" do
      let(:csv) do
        <<~CSV
          Txn Date,Value,Currency,Result
          not-a-date,oops,GBP,approved
        CSV
      end

      it "marks the statement as error without raising" do
        described_class.new(statement, mapping).call

        statement.reload
        expect(statement.status).to eq("error")
        expect(statement.error_message).to be_present
      end
    end

    context "when a date cell cannot be parsed" do
      let(:csv) do
        <<~CSV
          Txn Date,Value,Currency,Result
          not-a-date,100.00,GBP,approved
          2026-04-15,50.00,GBP,declined
        CSV
      end

      it "records the row and field details without exposing another row" do
        described_class.new(statement, mapping).call

        statement.reload
        expect(statement.error_message).to eq(
          'Row 2, field "date", column "Txn Date", value "not-a-date": invalid date'
        )
        expect(statement.error_message).not_to include(
          "100.00", "GBP", "approved", "2026-04-15", "50.00", "declined"
        )
      end
    end

    context "when an amount cell cannot be parsed" do
      let(:csv) do
        <<~CSV
          Txn Date,Value,Currency,Result
          2026-04-01,not-an-amount,GBP,approved
          2026-04-15,50.00,GBP,declined
        CSV
      end

      it "records the row and field details without exposing another row" do
        described_class.new(statement, mapping).call

        statement.reload
        expect(statement.error_message).to eq(
          'Row 2, field "amount", column "Value", value "not-an-amount": invalid amount'
        )
        expect(statement.error_message).not_to include(
          "2026-04-01", "GBP", "approved", "2026-04-15", "50.00", "declined"
        )
      end
    end

    context "when a currency cell cannot be parsed" do
      let(:csv) do
        <<~CSV
          Txn Date,Value,Currency,Result
          2026-04-01,100.00,not-a-currency,approved
          2026-04-15,50.00,GBP,declined
        CSV
      end

      it "records the row and field details without exposing another row" do
        described_class.new(statement, mapping).call

        statement.reload
        expect(statement.error_message).to eq(
          'Row 2, field "currency", column "Currency", value "not-a-currency": invalid currency code'
        )
        expect(statement.error_message).not_to include(
          "2026-04-01", "100.00", "approved", "2026-04-15", "50.00", "declined"
        )
      end
    end

    context "when a mapped column is missing from a row (malformed/ragged file)" do
      it "marks the statement as error without raising a KeyError" do
        reader = instance_double(Statements::SpreadsheetReader, row_count!: 1,
          each_row_hash: [ { "Txn Date" => "2026-04-01", "Value" => "10", "Currency" => "GBP" } ].each) # no "Result" key
        allow(Statements::SpreadsheetReader).to receive(:new).with(statement).and_return(reader)

        described_class.new(statement, mapping).call

        statement.reload
        expect(statement.status).to eq("error")
        expect(statement.error_message).to be_present
      end
    end

    context "when the underlying spreadsheet parser raises an unexpected error" do
      it "marks the statement as error without raising (never leaves it stuck queued)" do
        reader = instance_double(Statements::SpreadsheetReader)
        allow(reader).to receive(:row_count!).and_raise(Zip::Error, "corrupt archive")
        allow(Statements::SpreadsheetReader).to receive(:new).with(statement).and_return(reader)

        described_class.new(statement, mapping).call

        statement.reload
        expect(statement.status).to eq("error")
        expect(statement.error_message).to eq("Import failed while processing statement data.")
      end
    end

    context "when currency values need normalizing" do
      let(:csv) do
        <<~CSV
          Txn Date,Value,Currency,Result
          2026-04-01,100.00, gbp ,approved
          2026-04-02,50.00,GBP,approved
        CSV
      end

      it "strips and upcases currency codes so equivalent values aren't split apart" do
        described_class.new(statement, mapping).call

        statement.reload
        expect(statement.metrics["overall"]["total_volume"]).to eq({ "GBP" => "150.0" })
      end
    end

    context "when a currency value isn't a plausible ISO code (also closes the CSV-injection vector)" do
      let(:csv) do
        <<~CSV
          Txn Date,Value,Currency,Result
          2026-04-01,100.00,=1+1,approved
        CSV
      end

      it "marks the statement as error without raising" do
        described_class.new(statement, mapping).call

        statement.reload
        expect(statement.status).to eq("error")
        expect(statement.error_message).to match(/currency/i)
      end
    end

    context "when parsing an ISO-8601-shaped date" do
      let(:csv) do
        <<~CSV
          Txn Date,Value,Currency,Result
          2026-04-05,100.00,GBP,approved
        CSV
      end

      it "prefers the unambiguous ISO 8601 reading over Date.parse's guess" do
        described_class.new(statement, mapping).call

        statement.reload
        expect(statement.metrics["by_month"].keys).to eq([ "2026-04" ])
      end
    end

    context "when a newer mapping submission has superseded this job" do
      it "no-ops instead of overwriting the newer submission's eventual result" do
        newer_mapping = { "date" => "Txn Date", "amount" => "Value", "currency" => "Currency", "outcome" => "Result" }
        stale_mapping = { "date" => "Txn Date", "amount" => "Value", "currency" => "Currency", "outcome" => "Currency" }
        statement.update!(status: :mapped, column_mapping: newer_mapping)

        described_class.new(statement, stale_mapping).call

        statement.reload
        expect(statement.status).to eq("mapped")
        expect(statement.metrics).to eq({})
      end
    end
  end
end
