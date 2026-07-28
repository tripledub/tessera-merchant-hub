# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::DocumentReplacementRequirement, type: :model do
  let_it_be(:document) { create(:kyc_document, status: :complete) }

  describe "validations" do
    it "is valid with a document and opened_at" do
      requirement = build(:kyc_document_replacement_requirement, kyc_document: document)

      expect(requirement).to be_valid
    end

    it "requires opened_at" do
      requirement = build(:kyc_document_replacement_requirement, kyc_document: document, opened_at: nil)

      expect(requirement).not_to be_valid
    end
  end

  describe "uniqueness" do
    it "rejects a second requirement for the same document at the app level" do
      create(:kyc_document_replacement_requirement, kyc_document: document)
      duplicate = build(:kyc_document_replacement_requirement, kyc_document: document)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:kyc_document_id]).to be_present
    end

    it "rejects a second requirement for the same document at the database level" do
      create(:kyc_document_replacement_requirement, kyc_document: document)
      duplicate = build(:kyc_document_replacement_requirement, kyc_document: document)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "#escalate!" do
    it "transitions warned to escalated and stamps escalated_at" do
      requirement = create(:kyc_document_replacement_requirement, kyc_document: document, status: :warned)

      requirement.escalate!(at: Time.zone.local(2026, 1, 1))

      expect(requirement.reload).to be_escalated
      expect(requirement.escalated_at).to eq(Time.zone.local(2026, 1, 1))
    end

    it "is a no-op when already escalated" do
      requirement = create(:kyc_document_replacement_requirement, kyc_document: document, status: :escalated,
                            escalated_at: Time.zone.local(2026, 1, 1))

      requirement.escalate!(at: Time.zone.local(2026, 6, 1))

      expect(requirement.reload.escalated_at).to eq(Time.zone.local(2026, 1, 1))
    end

    it "is a no-op when already closed" do
      other_document = create(:kyc_document, status: :complete)
      requirement = create(:kyc_document_replacement_requirement, kyc_document: document, status: :closed,
                            closed_at: Time.current, superseded_by_kyc_document: other_document)

      requirement.escalate!

      expect(requirement.reload).to be_closed
    end
  end

  describe "#close!" do
    it "transitions to closed, stamping closed_at and superseded_by_kyc_document" do
      replacement = create(:kyc_document, status: :complete)
      requirement = create(:kyc_document_replacement_requirement, kyc_document: document, status: :escalated)

      requirement.close!(superseded_by: replacement, at: Time.zone.local(2026, 2, 1))

      requirement.reload
      expect(requirement).to be_closed
      expect(requirement.closed_at).to eq(Time.zone.local(2026, 2, 1))
      expect(requirement.superseded_by_kyc_document).to eq(replacement)
    end

    it "is a no-op when already closed" do
      first_replacement = create(:kyc_document, status: :complete)
      second_replacement = create(:kyc_document, status: :complete)
      requirement = create(:kyc_document_replacement_requirement, kyc_document: document, status: :closed,
                            closed_at: Time.zone.local(2026, 1, 1), superseded_by_kyc_document: first_replacement)

      requirement.close!(superseded_by: second_replacement, at: Time.zone.local(2026, 6, 1))

      requirement.reload
      expect(requirement.closed_at).to eq(Time.zone.local(2026, 1, 1))
      expect(requirement.superseded_by_kyc_document).to eq(first_replacement)
    end
  end

  describe ".current_for" do
    it "returns the single requirement row for a document, if any" do
      requirement = create(:kyc_document_replacement_requirement, kyc_document: document)

      expect(described_class.current_for(document)).to eq(requirement)
    end

    it "returns nil when no requirement exists" do
      expect(described_class.current_for(document)).to be_nil
    end
  end
end
