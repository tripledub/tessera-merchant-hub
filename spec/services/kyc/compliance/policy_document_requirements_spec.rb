# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::Compliance::PolicyDocumentRequirements, type: :service do
  subject(:results) { described_class.evaluate(applicant) }

  before do
    Kyc::PolicyRegistry.instance = Kyc::PolicyRegistry.load!
  end

  context "when the applicant is a Crypto Exchange" do
    let(:applicant) { create(:applicant, sector: :crypto_exchange) }

    it "returns one unmet result for each missing required-document policy" do
      expect(results.map do |result|
        [ result.requirement_id, result.title, result.status, result.entity, result.outcome ]
      end).to eq(
        [
          [ "crypto.vasp_registration", "VASP registration", :unmet, nil, "blocking" ],
          [
            "crypto.wallet_custody_infrastructure_attestation",
            "Wallet and custody infrastructure attestation",
            :unmet,
            nil,
            "blocking"
          ]
        ]
      )
      expect(results.map(&:missing)).to eq(
        [ [ "vasp_registration" ], [ "wallet_custody_infrastructure_attestation" ] ]
      )
      expect(results).to all(be_blocks_automated_completion)
    end

    it "marks each requirement met when a matching current document exists" do
      create(:kyc_document, applicant: applicant, document_type: :vasp_registration)
      create(:kyc_document, applicant: applicant, document_type: :wallet_custody_infrastructure_attestation)

      expect(results.map(&:status)).to eq([ :met, :met ])
      expect(results.map(&:satisfied)).to eq(
        [ [ "vasp_registration" ], [ "wallet_custody_infrastructure_attestation" ] ]
      )
      expect(results.map(&:missing)).to eq([ [], [] ])
    end

    it "does not satisfy a requirement with a superseded matching document" do
      replacement = create(:kyc_document, applicant: applicant, document_type: :passport)
      create(
        :kyc_document,
        applicant: applicant,
        document_type: :vasp_registration,
        superseded_by_kyc_document: replacement
      )

      vasp_result = results.find { |result| result.requirement_id == "crypto.vasp_registration" }

      expect(vasp_result).to be_unmet
    end
  end

  context "when the applicant is general" do
    let(:applicant) { create(:applicant, sector: :general) }

    it "returns no applicant-level document requirements" do
      expect(results).to be_empty
    end
  end

  context "with a warning required-document policy" do
    let(:applicant) { create(:applicant, sector: :general) }
    let(:warning_requirement) do
      Kyc::PolicyRequirement.new(
        id: "test.optional_policy",
        rule: "required_document",
        outcome: "warning",
        title: "Optional policy",
        guidance: "Upload the optional policy when available.",
        source: "test",
        parameters: { "document_type" => "aml_ctf_policy", "subject" => "applicant" }
      )
    end

    before do
      allow(Kyc::EffectivePolicy).to receive(:for).with(applicant).and_return([ warning_requirement ])
    end

    it "does not block automated completion when unmet" do
      expect(results.first).to be_unmet
      expect(results.first).not_to be_blocks_automated_completion
    end
  end
end
