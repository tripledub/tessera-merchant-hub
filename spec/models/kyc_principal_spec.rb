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

  # MH-331
  describe "merging" do
    it "belongs to merged_into optionally" do
      expect(principal).to belong_to(:merged_into).class_name("KycPrincipal").optional
    end

    it "is not merged by default" do
      expect(principal).not_to be_merged
    end

    it "is merged once merged_into is set" do
      applicant = create(:applicant)
      survivor = create(:kyc_principal, applicant: applicant)
      loser = create(:kyc_principal, applicant: applicant, merged_into: survivor)

      expect(loser).to be_merged
    end

    describe ".active" do
      it "excludes a merged-away principal" do
        applicant = create(:applicant)
        survivor = create(:kyc_principal, applicant: applicant)
        loser = create(:kyc_principal, applicant: applicant, merged_into: survivor)

        expect(described_class.active).to include(survivor)
        expect(described_class.active).not_to include(loser)
      end
    end
  end
end
