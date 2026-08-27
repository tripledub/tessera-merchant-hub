# frozen_string_literal: true

require "rails_helper"

RSpec.describe Statements::SpreadsheetReader do
  def statement_with(csv_content, filename: "statement.csv")
    statement = build(:processing_statement)
    statement.file.attach(
      io: StringIO.new(csv_content),
      filename: filename,
      content_type: "text/csv"
    )
    statement.save!(validate: false)
    statement
  end

  def xls_bytes(rows)
    require "spreadsheet"
    book = Spreadsheet::Workbook.new
    sheet = book.create_worksheet
    rows.each_with_index { |row, i| sheet.row(i).concat(row) }
    io = StringIO.new
    book.write(io)
    io.string
  end

  describe "#headers" do
    it "returns the first row as column headers" do
      statement = statement_with("Date,Amount,Currency,Status\n2026-04-01,10.00,GBP,approved\n")

      expect(described_class.new(statement).headers).to eq(%w[Date Amount Currency Status])
    end

    it "reads a real legacy .xls file (not just .xlsx/.csv)" do
      statement = build(:processing_statement)
      statement.file.attach(
        io: StringIO.new(xls_bytes([ [ "Date", "Amount" ], [ "2026-04-01", 10 ] ])),
        filename: "statement.xls",
        content_type: "application/vnd.ms-excel"
      )
      statement.save!(validate: false)

      expect(described_class.new(statement).headers).to eq(%w[Date Amount])
    end

    it "handles an uppercase file extension" do
      statement = statement_with("Date,Amount\n2026-04-01,10\n", filename: "STATEMENT.CSV")

      expect(described_class.new(statement).headers).to eq(%w[Date Amount])
    end
  end

  describe "#row_count" do
    it "counts data rows, excluding the header" do
      statement = statement_with("Date,Amount\n2026-04-01,10\n2026-04-02,20\n2026-04-03,30\n")

      expect(described_class.new(statement).row_count).to eq(3)
    end
  end

  describe "#each_row_hash" do
    it "yields each data row as a hash keyed by header" do
      statement = statement_with("Date,Amount\n2026-04-01,10\n2026-04-02,20\n")

      rows = described_class.new(statement).each_row_hash.to_a

      expect(rows).to eq([
        { "Date" => "2026-04-01", "Amount" => "10" },
        { "Date" => "2026-04-02", "Amount" => "20" }
      ])
    end
  end

  describe "row limit" do
    it "raises RowLimitExceeded when the statement has more rows than ProcessingStatement::MAX_ROWS" do
      stub_const("ProcessingStatement::MAX_ROWS", 2)
      statement = statement_with("Date,Amount\n2026-04-01,10\n2026-04-02,20\n2026-04-03,30\n")

      expect { described_class.new(statement).row_count! }
        .to raise_error(Statements::SpreadsheetReader::RowLimitExceeded, /2/)
    end

    it "does not raise when within the limit" do
      stub_const("ProcessingStatement::MAX_ROWS", 5)
      statement = statement_with("Date,Amount\n2026-04-01,10\n2026-04-02,20\n")

      expect(described_class.new(statement).row_count!).to eq(2)
    end
  end
end
