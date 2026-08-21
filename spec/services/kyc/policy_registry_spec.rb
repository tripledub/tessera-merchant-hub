# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe Kyc::PolicyRegistry do
  let(:fixture_path) { Pathname(Dir.mktmpdir("kyc-policies")) }

  after { FileUtils.remove_entry(fixture_path) if fixture_path.exist? }

  def write_policy(filename, contents)
    fixture_path.join(filename).write(contents)
  end

  def required_document(id: "crypto.vasp_registration", source: "1.1", document_type: "vasp_registration")
    <<~YAML
      - id: #{id}
        rule: required_document
        outcome: blocking
        title: VASP registration
        guidance: Upload evidence of the applicant's VASP registration.
        source: "#{source}"
        parameters:
          document_type: #{document_type}
          subject: applicant
    YAML
  end

  def policy_yaml(sector: "crypto_exchange", requirements: required_document)
    <<~YAML
      schema_version: 1
      sector: #{sector}
      requirements:
      #{requirements.indent(2)}
    YAML
  end

  def base_requirement(id: "base.passport_validity")
    <<~YAML
      - id: #{id}
        rule: document_validity
        outcome: blocking
        title: Passport validity
        guidance: Use the latest passport validity policy.
        source: MH-193
        parameters:
          document_type: passport
          version: 2
          effective_from: "2026-08-21"
          mode: expires
          required_dates:
            - expiry
          warning_thresholds:
            - 90
            - 30
          blocking: true
    YAML
  end

  describe ".load!" do
    it "loads requirements into deeply immutable value objects" do
      write_policy("crypto_exchange.yml", policy_yaml)

      registry = described_class.load!(path: fixture_path)
      requirement = registry.requirements_for("crypto_exchange").find do |entry|
        entry.id == "crypto.vasp_registration"
      end

      expect(requirement.rule).to eq("required_document")
      expect(requirement.outcome).to eq("blocking")
      expect(requirement.title).to eq("VASP registration")
      expect(requirement.guidance).to eq("Upload evidence of the applicant's VASP registration.")
      expect(requirement.source).to eq("1.1")
      expect(requirement.parameters).to eq(
        "document_type" => "vasp_registration",
        "subject" => "applicant"
      )
      expect(requirement).to be_frozen
      expect(requirement.parameters).to be_frozen
      expect(registry.requirements_for("crypto_exchange")).to be_frozen
    end

    it "parses quoted ISO effective dates after safe YAML loading" do
      write_policy("base.yml", policy_yaml(sector: "base", requirements: base_requirement))

      requirement = described_class.load!(path: fixture_path).requirements_for("general").first

      expect(requirement.parameters.fetch("effective_from")).to eq(Date.new(2026, 8, 21))
      expect(requirement.parameters.fetch("required_dates")).to be_frozen
      expect(requirement.parameters.fetch("warning_thresholds")).to be_frozen
    end

    it "rejects arbitrary Ruby objects without deserializing them" do
      write_policy("unsafe.yml", <<~YAML)
        --- !ruby/object:ERB
        src: puts('unsafe')
      YAML

      expect do
        described_class.load!(path: fixture_path)
      end.to raise_error(Kyc::PolicyRegistry::InvalidPolicy, /unsafe\.yml.*safe YAML/i)
    end

    it "rejects unsupported schema versions with the filename" do
      write_policy("unsupported.yml", policy_yaml.sub("schema_version: 1", "schema_version: 2"))

      expect do
        described_class.load!(path: fixture_path)
      end.to raise_error(Kyc::PolicyRegistry::InvalidPolicy, /unsupported\.yml.*schema_version/i)
    end

    it "rejects unsupported sectors with the filename" do
      write_policy("unsupported.yml", policy_yaml(sector: "unregulated_sector"))

      expect do
        described_class.load!(path: fixture_path)
      end.to raise_error(Kyc::PolicyRegistry::InvalidPolicy, /unsupported\.yml.*sector/i)
    end

    it "rejects unsupported rules with the filename and requirement ID" do
      write_policy("unsupported.yml", policy_yaml.sub("rule: required_document", "rule: manual_review"))

      expect do
        described_class.load!(path: fixture_path)
      end.to raise_error(
        Kyc::PolicyRegistry::InvalidPolicy,
        /unsupported\.yml.*crypto\.vasp_registration.*rule/i
      )
    end

    it "rejects unsupported outcomes with the filename and requirement ID" do
      write_policy("unsupported.yml", policy_yaml.sub("outcome: blocking", "outcome: advisory"))

      expect do
        described_class.load!(path: fixture_path)
      end.to raise_error(
        Kyc::PolicyRegistry::InvalidPolicy,
        /unsupported\.yml.*crypto\.vasp_registration.*outcome/i
      )
    end

    it "rejects missing top-level keys with the filename" do
      write_policy("missing.yml", policy_yaml.sub("schema_version: 1\n", ""))

      expect do
        described_class.load!(path: fixture_path)
      end.to raise_error(Kyc::PolicyRegistry::InvalidPolicy, /missing\.yml.*schema_version/i)
    end

    it "rejects missing requirement keys with the filename and requirement ID" do
      write_policy("missing.yml", policy_yaml.sub(/^\s*source: "1\.1"\n/, ""))

      expect do
        described_class.load!(path: fixture_path)
      end.to raise_error(Kyc::PolicyRegistry::InvalidPolicy, /missing\.yml.*crypto\.vasp_registration.*source/i)
    end

    it "rejects unknown document types with the filename and requirement ID" do
      write_policy("unknown.yml", policy_yaml(requirements: required_document(document_type: "unknown_document")))

      expect do
        described_class.load!(path: fixture_path)
      end.to raise_error(
        Kyc::PolicyRegistry::InvalidPolicy,
        /unknown\.yml.*crypto\.vasp_registration.*document_type/i
      )
    end

    it "rejects duplicate requirement IDs with both filename and requirement ID" do
      write_policy("duplicate.yml", policy_yaml(requirements: required_document + required_document))

      expect do
        described_class.load!(path: fixture_path)
      end.to raise_error(
        Kyc::PolicyRegistry::InvalidPolicy,
        /duplicate\.yml.*crypto\.vasp_registration.*duplicate/i
      )
    end

    it "rejects parameters that are not allowed for the rule" do
      requirements = required_document.sub(
        /^(\s*)subject: applicant$/,
        "\\1subject: applicant\n\\1warning_thresholds: []"
      )
      write_policy("parameters.yml", policy_yaml(requirements: requirements))

      expect do
        described_class.load!(path: fixture_path)
      end.to raise_error(
        Kyc::PolicyRegistry::InvalidPolicy,
        /parameters\.yml.*crypto\.vasp_registration.*warning_thresholds/i
      )
    end

    it "rejects unsupported required-document subjects" do
      write_policy("subject.yml", policy_yaml.sub("subject: applicant", "subject: director"))

      expect do
        described_class.load!(path: fixture_path)
      end.to raise_error(
        Kyc::PolicyRegistry::InvalidPolicy,
        /subject\.yml.*crypto\.vasp_registration.*subject/i
      )
    end
  end

  describe "#requirements_for" do
    it "returns only base requirements for the general sector" do
      write_policy("base.yml", policy_yaml(sector: "base", requirements: base_requirement))
      write_policy("crypto_exchange.yml", policy_yaml)

      requirements = described_class.load!(path: fixture_path).requirements_for("general")

      expect(requirements.map(&:id)).to eq([ "base.passport_validity" ])
      expect(requirements).to be_frozen
    end

    it "composes base requirements with the requested sector overlay" do
      write_policy("base.yml", policy_yaml(sector: "base", requirements: base_requirement))
      write_policy("crypto_exchange.yml", policy_yaml)

      requirements = described_class.load!(path: fixture_path).requirements_for("crypto_exchange")

      expect(requirements.map(&:id)).to eq([ "base.passport_validity", "crypto.vasp_registration" ])
      expect(requirements).to be_frozen
    end

    it "rejects a requirement ID duplicated across the base and an overlay" do
      write_policy("base.yml", policy_yaml(sector: "base", requirements: base_requirement))
      write_policy(
        "crypto_exchange.yml",
        policy_yaml(requirements: required_document(id: "base.passport_validity"))
      )

      expect do
        described_class.load!(path: fixture_path)
      end.to raise_error(
        Kyc::PolicyRegistry::InvalidPolicy,
        /crypto_exchange\.yml.*base\.passport_validity.*duplicate/i
      )
    end
  end
end
