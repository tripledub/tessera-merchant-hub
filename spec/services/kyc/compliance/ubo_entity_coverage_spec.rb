# frozen_string_literal: true

require "rails_helper"

# MH-251: a UBO flagged from registry data (no ownership entity attached) must
# not vanish from readiness just because nobody has captured it as an entity.
RSpec.describe Kyc::Compliance::UboEntityCoverage, type: :service do
  let(:applicant) { create(:applicant) }
  let(:document) { create(:kyc_document, applicant: applicant) }

  def registry_ubo!(name)
    create(:kyc_validation_warning, applicant: applicant, kyc_document: nil, corporate_entity: nil,
                                    warning_type: :ubo_threshold_exceeded, message: "UBO identified",
                                    metadata: { individual_name: name, effective_percentage: 75.0 })
  end

  it "returns nothing when the applicant has no registry-derived UBO warnings" do
    expect(described_class.evaluate(applicant)).to eq([])
  end

  it "returns an unmet blocking result when the UBO is not captured as an entity" do
    registry_ubo!("Test Person")

    results = described_class.evaluate(applicant)

    expect(results.size).to eq(1)
    expect(results.first).to be_unmet
    expect(results.first).to be_blocks_automated_completion
    expect(results.first.missing).to eq([ "ownership_entity" ])
    expect(results.first.title).to include("Test Person")
  end

  it "is satisfied by a matching entity regardless of case, whitespace or entity type" do
    create(:kyc_corporate_entity, applicant: applicant, kyc_document: document, entity_type: :corporate, name: "Test Holdings Ltd")
    registry_ubo!("  test holdings LTD ")

    expect(described_class.evaluate(applicant)).to eq([])
  end

  it "does not count an entity belonging to another applicant" do
    create(:kyc_corporate_entity, applicant: create(:applicant), kyc_document: create(:kyc_document), entity_type: :individual, name: "Test Person")
    registry_ubo!("Test Person")

    expect(described_class.evaluate(applicant).size).to eq(1)
  end

  it "ignores UBO warnings already attached to an ownership entity" do
    entity = create(:kyc_corporate_entity, applicant: applicant, kyc_document: document, entity_type: :individual, name: "Test Person")
    create(:kyc_validation_warning, applicant: applicant, kyc_document: document, corporate_entity: entity,
                                    warning_type: :ubo_threshold_exceeded, metadata: { individual_name: "Someone Else" })

    expect(described_class.evaluate(applicant)).to eq([])
  end
end
