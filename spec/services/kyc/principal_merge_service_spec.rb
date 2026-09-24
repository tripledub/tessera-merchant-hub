# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::PrincipalMergeService do
  let_it_be(:applicant) { create(:applicant) }

  def call(survivor:, loser:)
    described_class.call(survivor: survivor, loser: loser)
  end

  describe "#call" do
    it "fails when survivor and loser are the same record" do
      principal = create(:kyc_principal, applicant: applicant)

      result = call(survivor: principal, loser: principal)

      expect(result).not_to be_success
      expect(result.errors[:base]).to be_present
    end

    it "fails across different applicants" do
      survivor = create(:kyc_principal, applicant: applicant)
      loser = create(:kyc_principal)

      result = call(survivor: survivor, loser: loser)

      expect(result).not_to be_success
    end

    it "fails when the loser has already been merged away" do
      survivor = create(:kyc_principal, applicant: applicant)
      other_survivor = create(:kyc_principal, applicant: applicant)
      loser = create(:kyc_principal, applicant: applicant, merged_into: other_survivor)

      result = call(survivor: survivor, loser: loser)

      expect(result).not_to be_success
    end

    it "fails when the survivor has already been merged away" do
      other_survivor = create(:kyc_principal, applicant: applicant)
      survivor = create(:kyc_principal, applicant: applicant, merged_into: other_survivor)
      loser = create(:kyc_principal, applicant: applicant)

      result = call(survivor: survivor, loser: loser)

      expect(result).not_to be_success
    end

    it "backfills a blank field on the survivor from the loser" do
      survivor = create(:kyc_principal, applicant: applicant, email: nil, city: nil)
      loser = create(:kyc_principal, applicant: applicant, email: "loser@example.com", city: "London")

      result = call(survivor: survivor, loser: loser)

      expect(result).to be_success
      expect(survivor.reload.email).to eq("loser@example.com")
      expect(survivor.reload.city).to eq("London")
    end

    it "never overwrites a non-empty field on the survivor" do
      survivor = create(:kyc_principal, applicant: applicant, email: "survivor@example.com")
      loser = create(:kyc_principal, applicant: applicant, email: "loser@example.com")

      call(survivor: survivor, loser: loser)

      expect(survivor.reload.email).to eq("survivor@example.com")
    end

    it "backfills an unspecified survivor's role from a specified loser" do
      survivor = create(:kyc_principal, applicant: applicant, role: :unspecified)
      loser = create(:kyc_principal, applicant: applicant, role: :shareholder)

      call(survivor: survivor, loser: loser)

      expect(survivor.reload.role).to eq("shareholder")
    end

    it "never overwrites a survivor's already-specified role" do
      survivor = create(:kyc_principal, applicant: applicant, role: :director)
      loser = create(:kyc_principal, applicant: applicant, role: :shareholder)

      call(survivor: survivor, loser: loser)

      expect(survivor.reload.role).to eq("director")
    end

    it "re-points the loser's documents onto the survivor" do
      survivor = create(:kyc_principal, applicant: applicant)
      loser = create(:kyc_principal, applicant: applicant)
      document = create(:kyc_document, applicant: applicant, kyc_principal: loser)

      call(survivor: survivor, loser: loser)

      expect(document.reload.kyc_principal).to eq(survivor)
    end

    it "soft-deletes the loser, keeping its original field values" do
      survivor = create(:kyc_principal, applicant: applicant)
      loser = create(:kyc_principal, applicant: applicant, name: "Original Loser Name")

      call(survivor: survivor, loser: loser)

      loser.reload
      expect(loser.merged_into).to eq(survivor)
      expect(loser.name).to eq("Original Loser Name")
      expect(KycPrincipal.exists?(loser.id)).to be true
    end
  end
end
