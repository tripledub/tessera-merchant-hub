# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::Synthetic::PassportMrz do
  subject(:mrz) do
    described_class.call(persona: persona, document_number: "L898902C3", expiry_date: Date.new(2012, 4, 15))
  end

  let(:persona) do
    build(:synthetic_persona, given_names: "Anna Maria", surname: "Eriksson",
      date_of_birth: Date.new(1974, 8, 12), sex: :female)
  end

  it "produces two 44-character TD3 lines" do
    expect(mrz.line1.length).to eq(44)
    expect(mrz.line2.length).to eq(44)
  end

  it "builds line1 as document type, issuing state and surname<<given names" do
    expect(mrz.line1).to start_with("P<UTOERIKSSON<<ANNA<MARIA")
  end

  it "embeds the document number, its check digit and the issuing state" do
    expect(mrz.line2).to start_with("L898902C36UTO")
  end

  it "computes the correct date-of-birth and expiry check digits (ICAO specimen vector)" do
    # document number(9) + check(1) + state(3) = offset 13: DOB(6) + check(1)
    expect(mrz.line2[13, 7]).to eq("7408122")
    # ...+ DOB+check(7) + sex(1) = offset 21: expiry(6) + check(1)
    expect(mrz.line2[21, 7]).to eq("1204159")
  end

  it "renders the persona's sex" do
    expect(mrz.line2[20]).to eq("F")
  end

  it "is deterministic for the same inputs" do
    other = described_class.call(persona: persona, document_number: "L898902C3", expiry_date: Date.new(2012, 4, 15))

    expect(other).to eq(mrz)
  end

  it "recomputes a correct composite check digit over document number, DOB, expiry and personal number fields" do
    document_field = mrz.line2[0, 10]
    dob_field = mrz.line2[13, 7]
    expiry_field = mrz.line2[21, 7]
    personal_field = mrz.line2[28, 15]
    composite = mrz.line2[43]

    expect(composite).to eq(Kyc::Synthetic::Mrz.check_digit(document_field + dob_field + expiry_field + personal_field))
  end

  context "when the document number is shorter than 9 characters" do
    it "pads it with the MRZ filler" do
      mrz = described_class.call(persona: persona, document_number: "ABC", expiry_date: Date.new(2012, 4, 15))

      expect(mrz.line2[0, 9]).to eq("ABC<<<<<<")
    end
  end
end
