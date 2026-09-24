# frozen_string_literal: true

require "rails_helper"

RSpec.describe Statements::ColumnMappingSuggester, type: :service do
  def call(headers)
    described_class.call(headers: headers)
  end

  it "matches an exact header name for each required field" do
    result = call(%w[Date Amount Currency Outcome])

    expect(result).to eq(
      "date" => "Date", "amount" => "Amount", "currency" => "Currency", "outcome" => "Outcome"
    )
  end

  it "matches case-insensitively" do
    result = call(%w[DATE amount CuRrEnCy outcome])

    expect(result).to eq(
      "date" => "DATE", "amount" => "amount", "currency" => "CuRrEnCy", "outcome" => "outcome"
    )
  end

  it "matches a synonym, not just the literal field name" do
    result = call([ "Transaction Date", "Txn Amount", "CCY", "Status" ])

    expect(result).to eq(
      "date" => "Transaction Date", "amount" => "Txn Amount", "currency" => "CCY", "outcome" => "Status"
    )
  end

  it "leaves a field out of the result when nothing matches, rather than guessing" do
    result = call([ "Reference", "Notes" ])

    expect(result).to eq({})
  end

  it "only suggests the fields it found a confident match for, leaving the rest unmapped" do
    result = call(%w[Date Reference])

    expect(result).to eq("date" => "Date")
  end

  it "does not match a header that merely contains a synonym as a substring" do
    result = call([ "Date of Birth" ])

    expect(result).to eq({})
  end
end
