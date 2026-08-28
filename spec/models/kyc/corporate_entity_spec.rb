# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::CorporateEntity, type: :model do
  subject(:entity) { described_class.new }

  describe "associations" do
    it { is_expected.to belong_to(:applicant) }
    it { is_expected.to belong_to(:kyc_document).optional }
    it { is_expected.to have_many(:child_edges).class_name("Kyc::OwnershipEdge").with_foreign_key(:parent_entity_id).dependent(:destroy) }
    it { is_expected.to have_many(:parent_edges).class_name("Kyc::OwnershipEdge").with_foreign_key(:child_entity_id).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:entity_type) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:entity_type).with_values(individual: 0, corporate: 1) }

    it {
      expect(entity).to define_enum_for(:source)
        .with_values(document_extracted: 0, applicant_declared: 1, registry_fetched: 2)
        .with_default(:document_extracted)
    }
  end

  it "can be created without a kyc_document" do
    registry_entity = build(:kyc_corporate_entity, kyc_document: nil, source: :registry_fetched)
    expect(registry_entity).to be_valid
  end
end
