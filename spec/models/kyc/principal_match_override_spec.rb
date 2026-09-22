# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::PrincipalMatchOverride do
  let_it_be(:applicant) { create(:applicant) }
  let_it_be(:principal) { create(:kyc_principal, applicant: applicant, source: :registry_fetched) }
  let_it_be(:document)  { create(:kyc_document, applicant: applicant) }
  let_it_be(:resolver)  { create(:user, :psp_admin) }

  it "is valid with a reason" do
    override = described_class.new(
      kyc_document: document, kyc_principal: principal, resolution: :link_anyway,
      reason: "Same person, OCR swapped day/month", resolved_by: resolver
    )

    expect(override).to be_valid
  end

  it "requires a reason" do
    override = described_class.new(
      kyc_document: document, kyc_principal: principal, resolution: :link_anyway,
      reason: nil, resolved_by: resolver
    )

    expect(override).not_to be_valid
    expect(override.errors[:reason]).to be_present
  end

  it "defines the resolution enum" do
    expect(described_class.resolutions).to eq("link_anyway" => 0, "different_person" => 1)
  end
end
