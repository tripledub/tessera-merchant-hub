# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::OwnershipEdge, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:parent_entity).class_name("Kyc::CorporateEntity") }
    it { is_expected.to belong_to(:child_entity).class_name("Kyc::CorporateEntity") }
    it { is_expected.to belong_to(:source_document).class_name("KycDocument").optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:relationship_type) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:relationship_type).with_values(equity: 0, nominee: 1, contractual: 2) }
    it { is_expected.to define_enum_for(:source).with_values(document_extracted: 0, applicant_declared: 1).with_default(:document_extracted) }
  end
end
