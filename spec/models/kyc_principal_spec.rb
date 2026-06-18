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
end
