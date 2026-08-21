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

  def freshness_requirement(required_date: "issued")
    <<~YAML
      - id: base.utility_bill_freshness
        rule: document_validity
        outcome: blocking
        title: Utility bill freshness
        guidance: Use the latest utility bill freshness policy.
        source: MH-193
        parameters:
          document_type: utility_bill
          version: 2
          effective_from: "2026-08-21"
          mode: freshness
          required_dates:
            - #{required_date}
          warning_thresholds: []
          max_age_months: 3
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

    it "rejects document-validity requirements outside the base policy" do
      write_policy(
        "crypto_exchange.yml",
        policy_yaml(sector: "crypto_exchange", requirements: base_requirement(id: "crypto.passport_validity"))
      )

      expect do
        described_class.load!(path: fixture_path)
      end.to raise_error(
        Kyc::PolicyRegistry::InvalidPolicy,
        /crypto_exchange\.yml.*crypto\.passport_validity.*document_validity.*base/i
      )
    end

    it "requires expires validity policies to declare the expiry date" do
      requirement = base_requirement.sub("- expiry", "- issued")
      write_policy("base.yml", policy_yaml(sector: "base", requirements: requirement))

      expect do
        described_class.load!(path: fixture_path)
      end.to raise_error(
        Kyc::PolicyRegistry::InvalidPolicy,
        /base\.yml.*base\.passport_validity.*expires.*expiry/i
      )
    end

    it "requires freshness validity policies to declare the issued date" do
      requirement = freshness_requirement(required_date: "expiry")
      write_policy("base.yml", policy_yaml(sector: "base", requirements: requirement))

      expect do
        described_class.load!(path: fixture_path)
      end.to raise_error(
        Kyc::PolicyRegistry::InvalidPolicy,
        /base\.yml.*base\.utility_bill_freshness.*freshness.*issued/i
      )
    end

    it "rejects warning outcomes for document-validity requirements" do
      requirement = base_requirement.sub("outcome: blocking", "outcome: warning")
      write_policy("base.yml", policy_yaml(sector: "base", requirements: requirement))

      expect do
        described_class.load!(path: fixture_path)
      end.to raise_error(
        Kyc::PolicyRegistry::InvalidPolicy,
        /base\.yml.*base\.passport_validity.*document_validity.*outcome.*blocking/i
      )
    end

    it "rejects nonblocking document-validity policies" do
      requirement = base_requirement.sub("blocking: true", "blocking: false")
      write_policy("base.yml", policy_yaml(sector: "base", requirements: requirement))

      expect do
        described_class.load!(path: fixture_path)
      end.to raise_error(
        Kyc::PolicyRegistry::InvalidPolicy,
        /base\.yml.*base\.passport_validity.*document_validity.*blocking.*true/i
      )
    end
  end

  describe "#requirements_for" do
    it "composes base requirements with a general overlay" do
      write_policy("base.yml", policy_yaml(sector: "base", requirements: base_requirement))
      write_policy(
        "general.yml",
        policy_yaml(
          sector: "general",
          requirements: required_document(id: "general.passport", document_type: "passport")
        )
      )
      write_policy("crypto_exchange.yml", policy_yaml)

      requirements = described_class.load!(path: fixture_path).requirements_for("general")

      expect(requirements.map(&:id)).to eq([ "base.passport_validity", "general.passport" ])
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

    it "allows mutually exclusive sector overlays to reuse a requirement ID" do
      write_policy("base.yml", policy_yaml(sector: "base", requirements: base_requirement))
      write_policy(
        "crypto_exchange.yml",
        policy_yaml(requirements: required_document(id: "sector.registration"))
      )
      write_policy(
        "gambling.yml",
        policy_yaml(
          sector: "gambling",
          requirements: required_document(id: "sector.registration", document_type: "passport")
        )
      )

      registry = described_class.load!(path: fixture_path)

      expect(registry.requirements_for("crypto_exchange").map(&:id)).to eq(
        [ "base.passport_validity", "sector.registration" ]
      )
      expect(registry.requirements_for("gambling").map(&:id)).to eq(
        [ "base.passport_validity", "sector.registration" ]
      )
    end
  end

  describe "Rails reloading" do
    it "rebuilds the deployed registry during a reload preparation cycle" do
      stale_registry = Object.new
      described_class.instance = stale_registry

      Rails.application.reloader.prepare!

      expect(described_class.instance).to be_a(described_class)
      expect(described_class.instance).not_to equal(stale_registry)
    end
  end
end
