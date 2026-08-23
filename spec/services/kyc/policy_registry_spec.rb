# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe Kyc::PolicyRegistry do
  let(:fixture_path) { Pathname(Dir.mktmpdir("kyc-policies")) }
  let(:translations) do
    {
      en: {
        kyc: {
          policy_requirements: {
            base: {
              passport_validity: {
                title: "Passport validity",
                guidance: "Use the latest passport validity policy."
              },
              utility_bill_freshness: {
                title: "Utility bill freshness",
                guidance: "Use the latest utility bill freshness policy."
              }
            },
            crypto: {
              vasp_registration: {
                title: "VASP registration",
                guidance: "Upload registration evidence."
              },
              wallet_custody_infrastructure_attestation: {
                title: "Wallet and custody infrastructure attestation",
                guidance: "Upload an attestation describing the applicant's wallet and custody infrastructure."
              }
            },
            general: {
              passport: {
                title: "Passport",
                guidance: "Upload the applicant's passport."
              }
            },
            sector: {
              registration: {
                title: "Sector registration",
                guidance: "Upload sector registration evidence."
              }
            }
          }
        }
      }
    }
  end
  let(:localized_vasp_translations) do
    {
      en: { kyc: { policy_requirements: { crypto: { vasp_registration: {
        title: "VASP registration",
        guidance: "Upload registration evidence."
      } } } } },
      fr: { kyc: { policy_requirements: { crypto: { vasp_registration: {
        title: "Enregistrement VASP",
        guidance: "Téléversez la preuve d’enregistrement."
      } } } } }
    }
  end

  around do |example|
    if example.metadata[:deployed_registry]
      example.run
    else
      original_backend = I18n.backend
      original_load_path = I18n.load_path
      original_available_locales = I18n.available_locales
      I18n.load_path = []
      I18n.backend = I18n::Backend::Simple.new
      begin
        example.run
      ensure
        I18n.backend = original_backend
        I18n.load_path = original_load_path
        I18n.available_locales = original_available_locales
      end
    end
  end

  before do |example|
    unless example.metadata[:deployed_registry]
      translations.each { |locale, values| I18n.backend.store_translations(locale, values) }
    end
  end

  after { FileUtils.remove_entry(fixture_path) if fixture_path.exist? }

  def write_policy(filename, contents)
    fixture_path.join(filename).write(contents)
  end

  def required_document(id: "crypto.vasp_registration", source: "1.1", document_type: "vasp_registration")
    <<~YAML
      - id: #{id}
        rule: required_document
        outcome: blocking
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
      I18n.available_locales = [ :en, :fr ]
      localized_vasp_translations.each { |locale, values| I18n.backend.store_translations(locale, values) }
      write_policy("crypto_exchange.yml", policy_yaml)

      registry = described_class.load!(path: fixture_path)
      requirement = registry.requirements_for("crypto_exchange").find { |entry| entry.id == "crypto.vasp_registration" }

      expect(requirement.rule).to eq("required_document")
      expect(requirement.outcome).to eq("blocking")
      expect(requirement.title).to eq("VASP registration")
      expect(requirement.guidance).to eq("Upload registration evidence.")
      I18n.with_locale(:fr) do
        expect(requirement.title).to eq("Enregistrement VASP")
        expect(requirement.guidance).to eq("Téléversez la preuve d’enregistrement.")
      end
      expect(requirement.source).to eq("1.1")
      expect(requirement.parameters).to eq(
        "document_type" => "vasp_registration",
        "subject" => "applicant"
      )
      expect([ requirement, requirement.parameters, registry.requirements_for("crypto_exchange") ]).to all(be_frozen)
    end

    context "when derived translations are missing" do
      it "rejects a requirement missing translations for an available locale" do
        self_translations = {
          en: { kyc: { policy_requirements: { crypto: { vasp_registration: {
            title: "VASP registration",
            guidance: "Upload registration evidence."
          } } } } }
        }
        I18n.backend = I18n::Backend::Simple.new
        self_translations.each { |locale, values| I18n.backend.store_translations(locale, values) }
        allow(I18n).to receive(:available_locales).and_return([ :en, :fr ])
        write_policy("crypto_exchange.yml", policy_yaml)

        expect do
          described_class.load!(path: fixture_path)
        end.to raise_error(
          Kyc::PolicyRegistry::InvalidPolicy,
          /crypto_exchange\.yml.*crypto\.vasp_registration.*fr.*kyc\.policy_requirements\.crypto\.vasp_registration\.title/i
        )
      end

      it "rejects a requirement missing its title translation" do
        self_translations = {
          en: { kyc: { policy_requirements: { crypto: { vasp_registration: {
            guidance: "Upload registration evidence."
          } } } } },
          fr: { kyc: { policy_requirements: { crypto: { vasp_registration: {
            title: "Enregistrement VASP",
            guidance: "Téléversez la preuve d’enregistrement."
          } } } } }
        }
        I18n.backend = I18n::Backend::Simple.new
        self_translations.each { |locale, values| I18n.backend.store_translations(locale, values) }
        allow(I18n).to receive(:available_locales).and_return([ :en ])
        write_policy("crypto_exchange.yml", policy_yaml)

        expect do
          described_class.load!(path: fixture_path)
        end.to raise_error(
          Kyc::PolicyRegistry::InvalidPolicy,
          /crypto_exchange\.yml.*crypto\.vasp_registration.*en.*kyc\.policy_requirements\.crypto\.vasp_registration\.title/i
        )
      end

      it "rejects a requirement missing its guidance translation" do
        self_translations = {
          en: { kyc: { policy_requirements: { crypto: { vasp_registration: {
            title: "VASP registration"
          } } } } },
          fr: { kyc: { policy_requirements: { crypto: { vasp_registration: {
            title: "Enregistrement VASP",
            guidance: "Téléversez la preuve d’enregistrement."
          } } } } }
        }
        I18n.backend = I18n::Backend::Simple.new
        self_translations.each { |locale, values| I18n.backend.store_translations(locale, values) }
        allow(I18n).to receive(:available_locales).and_return([ :en ])
        write_policy("crypto_exchange.yml", policy_yaml)

        expect do
          described_class.load!(path: fixture_path)
        end.to raise_error(
          Kyc::PolicyRegistry::InvalidPolicy,
          /crypto_exchange\.yml.*crypto\.vasp_registration.*en.*kyc\.policy_requirements\.crypto\.vasp_registration\.guidance/i
        )
      end
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
    it "loads translated deployed requirements and rebuilds them during a reload preparation cycle", :deployed_registry do
      stale_registry = Object.new
      described_class.instance = stale_registry

      Rails.application.reloader.prepare!

      expect(described_class.instance).to be_a(described_class)
      expect(described_class.instance).not_to equal(stale_registry)
      requirement = described_class.instance.requirements_for("crypto_exchange").find do |entry|
        entry.id == "crypto.vasp_registration"
      end
      expect(requirement.title).to eq("VASP registration")
      expect(requirement.guidance).to eq("Upload evidence of the applicant's VASP registration or authorisation.")
    end
  end
end
