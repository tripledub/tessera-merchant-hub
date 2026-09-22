# frozen_string_literal: true

require "rails_helper"

RSpec.describe KycPrincipal, type: :model do
  subject(:principal) { build(:kyc_principal) }

  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to belong_to(:applicant) }

  it "has many kyc_documents" do
    expect(principal).to have_many(:kyc_documents)
      .with_foreign_key(:kyc_principal_id)
      .dependent(:nullify)
  end

  it "defaults role to director" do
    expect(principal.role).to eq("director")
  end

  it "allows psc role" do
    principal.role = :psc
    expect(principal).to be_valid
  end

  it "allows secretary role" do
    principal.role = :secretary
    expect(principal).to be_valid
  end

  # MH-307: appended, not inserted — existing rows (0-4) must keep their
  # integer values. Never the enum/column default.
  it {
    expect(principal).to define_enum_for(:role)
      .with_values(director: 0, psc: 1, director_and_psc: 2, shareholder: 3, secretary: 4, unspecified: 5)
      .with_default(:director)
  }

  it "allows unspecified role" do
    principal.role = :unspecified
    expect(principal).to be_valid
  end

  it {
    expect(principal).to define_enum_for(:source)
      .with_values(document_extracted: 0, applicant_declared: 1, registry_fetched: 2)
      .with_default(:document_extracted)
  }
end
