# frozen_string_literal: true

module Statements
  class SpreadsheetReader
    class RowLimitExceeded < StandardError; end

    def initialize(processing_statement)
      @processing_statement = processing_statement
    end

    def headers
      open_spreadsheet { |sheet| sheet.row(1) }
    end

    # Roo's #last_row is metadata the parser already has — this does not
    # require building a Ruby array of every row's contents the way
    # each_row_hash does, so displaying the mapping screen (which only
    # needs headers + a count) stays cheap even for large files.
    def row_count
      open_spreadsheet { |sheet| sheet.last_row.to_i - 1 }
    end

    def row_count!
      count = row_count
      max = ProcessingStatement::MAX_ROWS
      if count > max
        raise RowLimitExceeded, "Statement has #{count} rows, which exceeds the limit of #{max}. " \
          "Please split the file and upload it in parts."
      end

      count
    end

    def each_row_hash
      return enum_for(:each_row_hash) unless block_given?

      open_spreadsheet do |sheet|
        header_row = sheet.row(1)
        (2..sheet.last_row).each { |i| yield header_row.zip(sheet.row(i)).to_h }
      end
    end

    private

    attr_reader :processing_statement

    # CSV parsing (via Roo::CSV) reads lazily from the file path rather
    # than loading everything at open time, so the tempfile must still
    # exist for as long as we're pulling data out of the parsed sheet —
    # every read has to happen inside this block rather than after it
    # returns.
    def open_spreadsheet
      blob = processing_statement.file.blob
      extension = File.extname(blob.filename.to_s).delete_prefix(".").downcase.presence || "csv"
      blob.open do |tempfile|
        yield Roo::Spreadsheet.open(tempfile.path, extension: extension.to_sym)
      end
    end
  end
end
