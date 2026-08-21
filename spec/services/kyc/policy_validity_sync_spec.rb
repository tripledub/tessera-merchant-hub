# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::PolicyValiditySync do
  def validity_requirement(id: nil, document_type:, version:, effective_from:, mode:, required_dates:,
                           warning_thresholds: [], max_age_months: nil, blocking: true)
    Kyc::PolicyRequirement.new(
      id: id || "base.#{document_type}_validity",
      rule: "document_validity",
      outcome: "blocking",
      title: "Document validity",
      guidance: "Apply the declared document validity policy.",
      source: "MH-193",
      parameters: {
        "document_type" => document_type,
        "version" => version,
        "effective_from" => effective_from,
        "mode" => mode,
        "required_dates" => required_dates,
        "warning_thresholds" => warning_thresholds,
        "max_age_months" => max_age_months,
        "blocking" => blocking
      }.freeze
    )
  end

  def registry_for(requirements_by_sector)
    instance_double(Kyc::PolicyRegistry).tap do |registry|
      allow(registry).to receive(:requirements_for) do |sector|
        requirements_by_sector.fetch(sector, [])
      end
    end
  end

  def passport_validity(id:, warning_thresholds: [])
    validity_requirement(
      id: id,
      document_type: "passport",
      version: 2,
      effective_from: Date.new(2026, 8, 21),
      mode: "expires",
      required_dates: [ "expiry" ],
      warning_thresholds: warning_thresholds
    )
  end

  def utility_bill_validity(id:)
    validity_requirement(
      id: id,
      document_type: "utility_bill",
      version: 2,
      effective_from: Date.new(2026, 8, 21),
      mode: "freshness",
      required_dates: [ "issued" ],
      max_age_months: 3
    )
  end

  let(:passport_requirement) do
    validity_requirement(
      document_type: "passport",
      version: 2,
      effective_from: Date.new(2026, 8, 21),
      mode: "expires",
      required_dates: [ "expiry" ],
      warning_thresholds: [ 90, 30 ]
    )
  end
  let(:utility_bill_requirement) do
    validity_requirement(
      document_type: "utility_bill",
      version: 2,
      effective_from: Date.new(2026, 8, 21),
      mode: "freshness",
      required_dates: [ "issued" ],
      max_age_months: 3
    )
  end
  let(:requirements) { [ passport_requirement, utility_bill_requirement ] }
  let(:registry) { instance_double(Kyc::PolicyRegistry, requirements_for: requirements) }

  it "creates every declared document-validity version" do
    expect { described_class.call(registry: registry) }
      .to change(Kyc::DocumentValidityPolicy, :count).by(2)

    expect(described_class.call(registry: registry)).to eq(created: 0, unchanged: 2)
    expect(Kyc::DocumentValidityPolicy.find_by!(document_type: "passport", version: 2)).to have_attributes(
      effective_from: Date.new(2026, 8, 21),
      mode: "expires",
      required_dates: [ "expiry" ],
      warning_thresholds: [ 90, 30 ],
      max_age_months: nil,
      blocking: true,
      enabled: true
    )
    expect(Kyc::DocumentValidityPolicy.find_by!(document_type: "utility_bill", version: 2)).to have_attributes(
      mode: "freshness",
      required_dates: [ "issued" ],
      warning_thresholds: [],
      max_age_months: 3,
      blocking: true,
      enabled: true
    )
  end

  it "is idempotent when every declared version already matches" do
    expect(described_class.call(registry: registry)).to eq(created: 2, unchanged: 0)

    result = nil
    expect { result = described_class.call(registry: registry) }
      .not_to change(Kyc::DocumentValidityPolicy, :count)
    expect(result).to eq(created: 0, unchanged: 2)
  end

  it "creates an explicitly declared version 2 when version 1 already exists" do
    version_one = Kyc::DocumentValidityPolicy.publish!(
      document_type: "passport",
      effective_from: Date.new(2025, 1, 1),
      mode: :expires,
      required_dates: [ "expiry" ]
    )
    passport_registry = instance_double(Kyc::PolicyRegistry, requirements_for: [ passport_requirement ])

    expect { described_class.call(registry: passport_registry) }
      .to change(Kyc::DocumentValidityPolicy, :count).by(1)

    expect(version_one.reload.version).to eq(1)
    expect(Kyc::DocumentValidityPolicy.find_by!(document_type: "passport", version: 2)).to have_attributes(
      effective_from: Date.new(2026, 8, 21),
      warning_thresholds: [ 90, 30 ]
    )
  end

  it "preserves linked historical assessments when adding a new version" do
    version_one = Kyc::DocumentValidityPolicy.publish!(
      document_type: "passport",
      effective_from: Date.new(2025, 1, 1),
      mode: :expires,
      required_dates: [ "expiry" ]
    )
    assessment = create(:kyc_document_validity_assessment, kyc_document_validity_policy: version_one,
                                                           policy_version: version_one.version)
    passport_registry = instance_double(Kyc::PolicyRegistry, requirements_for: [ passport_requirement ])

    described_class.call(registry: passport_registry)

    expect(assessment.reload.kyc_document_validity_policy).to eq(version_one)
    expect(assessment.policy_version).to eq(1)
    expect(Kyc::DocumentValidityPolicy.where(document_type: "passport").pluck(:version)).to contain_exactly(1, 2)
  end

  it "raises when a declared version collides with different immutable content" do
    Kyc::DocumentValidityPolicy.create!(
      document_type: "utility_bill",
      version: 2,
      effective_from: Date.new(2026, 8, 21),
      mode: :freshness,
      required_dates: [ "issued" ],
      warning_thresholds: [],
      max_age_months: 6,
      blocking: true
    )
    utility_registry = instance_double(Kyc::PolicyRegistry, requirements_for: [ utility_bill_requirement ])

    expect do
      described_class.call(registry: utility_registry)
    end.to raise_error(described_class::Conflict, /utility_bill.*version 2.*max_age_months/i)
  end

  it "projects distinct sibling-overlay definitions that reuse a requirement ID" do
    crypto_requirement = passport_validity(id: "shared.document_validity")
    gambling_requirement = utility_bill_validity(id: "shared.document_validity")
    sibling_registry = registry_for(
      "crypto_exchange" => [ crypto_requirement ],
      "gambling" => [ gambling_requirement ]
    )

    result = nil
    expect { result = described_class.call(registry: sibling_registry) }
      .to change(Kyc::DocumentValidityPolicy, :count).by(2)
    expect(result).to eq(created: 2, unchanged: 0)
    expect(Kyc::DocumentValidityPolicy.pluck(:document_type, :version)).to contain_exactly(
      [ "passport", 2 ], [ "utility_bill", 2 ]
    )
  end

  it "checks sibling-overlay definitions with a reused ID for immutable collisions" do
    crypto_requirement = passport_validity(id: "shared.passport_validity", warning_thresholds: [ 90 ])
    gambling_requirement = passport_validity(id: "shared.passport_validity", warning_thresholds: [ 30 ])
    sibling_registry = registry_for(
      "crypto_exchange" => [ crypto_requirement ],
      "gambling" => [ gambling_requirement ]
    )

    expect do
      described_class.call(registry: sibling_registry)
    end.to raise_error(described_class::Conflict, /passport.*version 2.*warning_thresholds/i)
    expect(Kyc::DocumentValidityPolicy.where(document_type: "passport", version: 2).count).to eq(1)
  end
end
