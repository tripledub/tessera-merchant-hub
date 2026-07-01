# MH-175: Document Category System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace scattered, duplicated `IDENTITY_DOC_TYPES`/`ADDRESS_DOC_TYPES` constants and hardcoded type checks (`document.utility_bill?`, `passport?`) with a single `Kyc::DocumentCategory` registry, and fix bank account statements / driving licences so they participate correctly in principal matching and address population.

**Architecture:** A new `Kyc::DocumentCategory` module owns the canonical `document_type → category` mapping. Two new concerns (`ExtractionData::Concerns::Identifiable`, `ExtractionData::Concerns::AddressProviding`) give each extraction schema a normalized interface (`person_full_name`, `person_date_of_birth`, `structured_address`, `to_matcher_hash`) so `PrincipalMatcherService` and `ExtractKycDocumentJob` stop reading field names directly off the raw response hash. `BankAccountStatement` gains structured address fields; `DrivingLicence`'s unused string `address` is replaced with structured fields. All consumers (`PrincipalMatcherService`, `ExtractKycDocumentJob`, `UboDocumentRequirements`, `DocumentCollectionService`) are updated to query the registry/concerns instead of hardcoding type lists.

**Tech Stack:** Ruby, Rails 8, RSpec, FactoryBot, StoreModel

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `app/services/kyc/document_category.rb` | Create | Canonical document_type → category registry |
| `spec/services/kyc/document_category_spec.rb` | Create | Registry behavior coverage |
| `app/models/extraction_data/concerns/identifiable.rb` | Create | `person_full_name` / `person_date_of_birth` / `to_matcher_hash` contract for identity docs |
| `app/models/extraction_data/concerns/address_providing.rb` | Create | `person_full_name` / `structured_address` / `to_matcher_hash` contract for proof-of-address docs |
| `app/models/extraction_data/passport.rb` | Modify | Include `Identifiable` |
| `app/models/extraction_data/driving_licence.rb` | Modify | Replace `address` string with structured fields; include `Identifiable` |
| `app/models/extraction_data/utility_bill.rb` | Modify | Include `AddressProviding` |
| `app/models/extraction_data/bank_account_statement.rb` | Modify | Add structured address fields; include `AddressProviding` |
| `app/jobs/extract_kyc_document_job.rb` | Modify | Use `Kyc::DocumentCategory` + typed extraction data instead of `document.utility_bill?` and raw hash field names |
| `app/services/principal_matcher_service.rb` | Modify | `dob_aware_identity?` replaces `passport?`, backed by the registry |
| `app/services/kyc/compliance/rules/ubo_document_requirements.rb` | Modify | Delete local `IDENTITY_DOC_TYPES`/`ADDRESS_DOC_TYPES`, use registry |
| `app/services/onboarding/document_collection_service.rb` | Modify | Delete local `IDENTITY_TYPES`/`ADDRESS_TYPES`, use registry |
| Specs for all modified files | Modify | Cover new behavior, regression-guard old |

---

### Task 1: Kyc::DocumentCategory registry

**Files:**
- Create: `app/services/kyc/document_category.rb`
- Test: `spec/services/kyc/document_category_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/kyc/document_category_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kyc::DocumentCategory do
  describe ".for" do
    it "returns :identity for passport" do
      expect(described_class.for("passport")).to eq(:identity)
    end

    it "returns :identity for driving_licence" do
      expect(described_class.for("driving_licence")).to eq(:identity)
    end

    it "returns :proof_of_address for utility_bill" do
      expect(described_class.for("utility_bill")).to eq(:proof_of_address)
    end

    it "returns :proof_of_address for bank_account_statement" do
      expect(described_class.for("bank_account_statement")).to eq(:proof_of_address)
    end

    it "accepts symbols as well as strings" do
      expect(described_class.for(:passport)).to eq(:identity)
    end

    it "returns nil for a document type with no category" do
      expect(described_class.for("certificate_of_incorporation")).to be_nil
    end
  end

  describe ".identity?" do
    it "is true for identity document types" do
      expect(described_class.identity?("passport")).to be true
    end

    it "is false for non-identity document types" do
      expect(described_class.identity?("utility_bill")).to be false
    end
  end

  describe ".proof_of_address?" do
    it "is true for proof-of-address document types" do
      expect(described_class.proof_of_address?("bank_account_statement")).to be true
    end

    it "is false for non-proof-of-address document types" do
      expect(described_class.proof_of_address?("passport")).to be false
    end
  end

  describe ".types_for" do
    it "returns all document types in a category" do
      expect(described_class.types_for(:identity)).to contain_exactly("passport", "driving_licence", "government_id")
    end

    it "returns an empty array for an unknown category" do
      expect(described_class.types_for(:nonexistent)).to eq([])
    end
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/services/kyc/document_category_spec.rb`
Expected: FAIL — `uninitialized constant Kyc::DocumentCategory`

- [ ] **Step 3: Implement the registry**

```ruby
# app/services/kyc/document_category.rb
# frozen_string_literal: true

module Kyc
  module DocumentCategory
    REGISTRY = {
      identity:         %w[passport driving_licence government_id],
      proof_of_address: %w[utility_bill bank_account_statement]
    }.freeze

    module_function

    def for(document_type)
      REGISTRY.find { |_, types| types.include?(document_type.to_s) }&.first
    end

    def identity?(document_type)
      self.for(document_type) == :identity
    end

    def proof_of_address?(document_type)
      self.for(document_type) == :proof_of_address
    end

    def types_for(category)
      REGISTRY.fetch(category, [])
    end
  end
end
```

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bundle exec rspec spec/services/kyc/document_category_spec.rb`
Expected: PASS — all 12 examples

- [ ] **Step 5: Commit**

```bash
git add app/services/kyc/document_category.rb spec/services/kyc/document_category_spec.rb
git commit -m "MH-175 Add Kyc::DocumentCategory registry"
```

---

### Task 2: Identifiable and AddressProviding concerns

**Files:**
- Create: `app/models/extraction_data/concerns/identifiable.rb`
- Create: `app/models/extraction_data/concerns/address_providing.rb`
- Modify: `app/models/extraction_data/passport.rb`
- Modify: `app/models/extraction_data/driving_licence.rb`
- Modify: `app/models/extraction_data/utility_bill.rb`
- Modify: `app/models/extraction_data/bank_account_statement.rb`
- Test: `spec/models/extraction_data/concerns/identifiable_spec.rb`
- Test: `spec/models/extraction_data/concerns/address_providing_spec.rb`

The concerns define an interface contract (`person_full_name`, etc.) but the field-name mapping is per-class, so each concern declares the methods as `NotImplementedError` stubs and each including class overrides them. This makes a class that forgets to map a field fail loudly instead of silently returning nil.

- [ ] **Step 1: Write the failing concern specs**

```ruby
# spec/models/extraction_data/concerns/identifiable_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExtractionData::Concerns::Identifiable do
  let(:dummy_class) do
    Class.new(ExtractionData::Base) { include ExtractionData::Concerns::Identifiable }
  end

  describe "#to_matcher_hash" do
    it "raises NotImplementedError if the including class doesn't override person_full_name" do
      expect { dummy_class.new.to_matcher_hash }.to raise_error(NotImplementedError)
    end
  end

  describe "ExtractionData::Passport" do
    it "maps full_name to person_full_name" do
      data = ExtractionData::Passport.new(full_name: "Jane Smith", date_of_birth: "1990-01-15")
      expect(data.person_full_name).to eq("Jane Smith")
      expect(data.person_date_of_birth).to eq(Date.parse("1990-01-15"))
    end

    it "builds a matcher hash" do
      data = ExtractionData::Passport.new(full_name: "Jane Smith", date_of_birth: "1990-01-15")
      expect(data.to_matcher_hash).to eq("full_name" => "Jane Smith", "date_of_birth" => Date.parse("1990-01-15"))
    end
  end

  describe "ExtractionData::DrivingLicence" do
    it "maps full_name and date_of_birth to the normalized interface" do
      data = ExtractionData::DrivingLicence.new(full_name: "John Doe", date_of_birth: "1985-03-20")
      expect(data.person_full_name).to eq("John Doe")
      expect(data.person_date_of_birth).to eq(Date.parse("1985-03-20"))
    end
  end
end
```

```ruby
# spec/models/extraction_data/concerns/address_providing_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExtractionData::Concerns::AddressProviding do
  let(:dummy_class) do
    Class.new(ExtractionData::Base) { include ExtractionData::Concerns::AddressProviding }
  end

  describe "#to_matcher_hash" do
    it "raises NotImplementedError if the including class doesn't override person_full_name" do
      expect { dummy_class.new.to_matcher_hash }.to raise_error(NotImplementedError)
    end
  end

  describe "ExtractionData::UtilityBill" do
    it "maps full_name to person_full_name" do
      data = ExtractionData::UtilityBill.new(full_name: "Jane Smith")
      expect(data.person_full_name).to eq("Jane Smith")
    end

    it "exposes a structured address" do
      data = ExtractionData::UtilityBill.new(
        full_name: "Jane Smith",
        account_holder_address_line1: "12 High Street",
        account_holder_city: "London",
        account_holder_postcode: "SW1A 1AA",
        account_holder_country: "United Kingdom"
      )
      expect(data.structured_address).to eq(
        line1: "12 High Street", city: "London", postcode: "SW1A 1AA", country: "United Kingdom"
      )
    end

    it "builds a matcher hash with no date_of_birth" do
      data = ExtractionData::UtilityBill.new(full_name: "Jane Smith")
      expect(data.to_matcher_hash).to eq("full_name" => "Jane Smith", "date_of_birth" => nil)
    end
  end

  describe "ExtractionData::BankAccountStatement" do
    it "maps account_holder to person_full_name" do
      data = ExtractionData::BankAccountStatement.new(account_holder: "Pieter Bakker", bank_name: "ING")
      expect(data.person_full_name).to eq("Pieter Bakker")
    end

    it "exposes a structured address from the new address fields" do
      data = ExtractionData::BankAccountStatement.new(
        account_holder: "Pieter Bakker",
        bank_name: "ING",
        account_holder_address_line1: "Willem Augustinstraat 190",
        account_holder_city: "Amsterdam",
        account_holder_postcode: "1061 MJ",
        account_holder_country: "Netherlands"
      )
      expect(data.structured_address).to eq(
        line1: "Willem Augustinstraat 190", city: "Amsterdam", postcode: "1061 MJ", country: "Netherlands"
      )
    end

    it "builds a matcher hash using account_holder as the name" do
      data = ExtractionData::BankAccountStatement.new(account_holder: "Pieter Bakker", bank_name: "ING")
      expect(data.to_matcher_hash).to eq("full_name" => "Pieter Bakker", "date_of_birth" => nil)
    end
  end
end
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `bundle exec rspec spec/models/extraction_data/concerns/`
Expected: FAIL — `uninitialized constant ExtractionData::Concerns::Identifiable` (and `AddressProviding`)

- [ ] **Step 3: Implement the concerns**

```ruby
# app/models/extraction_data/concerns/identifiable.rb
# frozen_string_literal: true

module ExtractionData
  module Concerns
    module Identifiable
      def person_full_name
        raise NotImplementedError, "#{self.class} must implement #person_full_name"
      end

      def person_date_of_birth
        raise NotImplementedError, "#{self.class} must implement #person_date_of_birth"
      end

      def to_matcher_hash
        { "full_name" => person_full_name, "date_of_birth" => person_date_of_birth }
      end
    end
  end
end
```

```ruby
# app/models/extraction_data/concerns/address_providing.rb
# frozen_string_literal: true

module ExtractionData
  module Concerns
    module AddressProviding
      def person_full_name
        raise NotImplementedError, "#{self.class} must implement #person_full_name"
      end

      def structured_address
        raise NotImplementedError, "#{self.class} must implement #structured_address"
      end

      def to_matcher_hash
        { "full_name" => person_full_name, "date_of_birth" => nil }
      end
    end
  end
end
```

- [ ] **Step 4: Update Passport to include Identifiable**

```ruby
# app/models/extraction_data/passport.rb
# frozen_string_literal: true

module ExtractionData
  class Passport < Base
    include Concerns::Identifiable

    register_as :passport

    attribute :full_name, :string
    attribute :date_of_birth, :date
    attribute :document_number, :string
    attribute :expiry_date, :date
    attribute :issuing_country, :string
    attribute :nationality, :string
    attribute :issuing_authority, :string

    validates :full_name, :document_number, :expiry_date, presence: true

    def person_full_name
      full_name
    end

    def person_date_of_birth
      date_of_birth
    end
  end
end
```

- [ ] **Step 5: Update DrivingLicence — structured address fields + Identifiable**

```ruby
# app/models/extraction_data/driving_licence.rb
# frozen_string_literal: true

module ExtractionData
  class DrivingLicence < Base
    include Concerns::Identifiable

    register_as :driving_licence

    attribute :full_name, :string
    attribute :date_of_birth, :date
    attribute :document_number, :string
    attribute :expiry_date, :date
    attribute :issuing_country, :string
    attribute :address_line1, :string
    attribute :city, :string
    attribute :postcode, :string
    attribute :country, :string

    validates :full_name, :document_number, :expiry_date, presence: true

    def person_full_name
      full_name
    end

    def person_date_of_birth
      date_of_birth
    end
  end
end
```

- [ ] **Step 6: Update UtilityBill to include AddressProviding**

```ruby
# app/models/extraction_data/utility_bill.rb
# frozen_string_literal: true

module ExtractionData
  class UtilityBill < Base
    include Concerns::AddressProviding

    register_as :utility_bill

    attribute :full_name, :string
    attribute :account_holder_address_line1, :string
    attribute :account_holder_city, :string
    attribute :account_holder_postcode, :string
    attribute :account_holder_country, :string
    attribute :provider, :string
    attribute :provider_address, :string
    attribute :issue_date, :date
    attribute :account_number, :string

    def person_full_name
      full_name
    end

    def structured_address
      {
        line1: account_holder_address_line1,
        city: account_holder_city,
        postcode: account_holder_postcode,
        country: account_holder_country
      }
    end
  end
end
```

- [ ] **Step 7: Update BankAccountStatement — add address fields + AddressProviding**

```ruby
# app/models/extraction_data/bank_account_statement.rb
# frozen_string_literal: true

module ExtractionData
  class BankAccountStatement < Base
    include Concerns::AddressProviding

    register_as :bank_account_statement

    attribute :account_holder, :string
    attribute :account_holder_address_line1, :string
    attribute :account_holder_city, :string
    attribute :account_holder_postcode, :string
    attribute :account_holder_country, :string
    attribute :bank_name, :string
    attribute :account_number, :string
    attribute :sort_code, :string
    attribute :iban, :string
    attribute :currency, :string
    attribute :statement_period_start, :date
    attribute :statement_period_end, :date
    attribute :opening_balance, :string
    attribute :closing_balance, :string

    validates :account_holder, :bank_name, presence: true

    def person_full_name
      account_holder
    end

    def structured_address
      {
        line1: account_holder_address_line1,
        city: account_holder_city,
        postcode: account_holder_postcode,
        country: account_holder_country
      }
    end
  end
end
```

- [ ] **Step 8: Run the concern specs to verify they pass**

Run: `bundle exec rspec spec/models/extraction_data/concerns/`
Expected: PASS — all examples

- [ ] **Step 9: Run the full extraction_data spec to check for regressions**

Run: `bundle exec rspec spec/models/extraction_data_spec.rb`
Expected: PASS — no regressions from the `DrivingLicence` field rename (`address` → `address_line1`/`city`/`postcode`/`country`). If this spec references the old `address` field, update it to use the new structured fields.

- [ ] **Step 10: Commit**

```bash
git add app/models/extraction_data/concerns/ app/models/extraction_data/passport.rb \
        app/models/extraction_data/driving_licence.rb app/models/extraction_data/utility_bill.rb \
        app/models/extraction_data/bank_account_statement.rb \
        spec/models/extraction_data/concerns/ spec/models/extraction_data_spec.rb
git commit -m "MH-175 Add Identifiable/AddressProviding concerns to ExtractionData schemas"
```

---

### Task 3: PrincipalMatcherService uses the category registry and typed data

**Files:**
- Modify: `app/services/principal_matcher_service.rb`
- Modify: `spec/services/principal_matcher_service_spec.rb`

`PrincipalMatcherService` currently checks `@document_type == "passport"` for both DOB-aware exact matching and auto-creation. Split these: DOB-aware matching should apply to **all identity documents** (passport and driving licence); auto-creation remains **passport-only** (a deliberate policy choice — see design spec "Out of Scope").

- [ ] **Step 1: Add a failing test for driving-licence DOB-aware matching**

In `spec/services/principal_matcher_service_spec.rb`, add a new context after the existing `"when the name matches exactly but DOB differs (passport)"` context:

```ruby
    context "when the name matches exactly but DOB differs (driving licence)" do
      let!(:principal) { create(:kyc_principal, applicant: applicant, name: "John Smith", date_of_birth: "1990-01-15") }
      let(:result_data) { { "full_name" => "John Smith", "date_of_birth" => "1985-06-20" } }

      it "does not exact-match; falls through to fuzzy (DOB-aware matching applies beyond passports)" do
        result = described_class.call(applicant: applicant, document_type: "driving_licence", result: result_data)

        expect(result.match_method).to eq("fuzzy")
      end
    end

    context "when there is an exact name + DOB match on a driving licence" do
      let!(:principal) { create(:kyc_principal, applicant: applicant, name: "John Smith", date_of_birth: "1990-01-15") }
      let(:result_data) { { "full_name" => "John Smith", "date_of_birth" => "1990-01-15" } }

      it "matches exactly, same as a passport would" do
        result = described_class.call(applicant: applicant, document_type: "driving_licence", result: result_data)

        expect(result.principal).to eq(principal)
        expect(result.match_method).to eq("exact")
      end
    end
```

- [ ] **Step 2: Run the spec to verify the new tests fail**

Run: `bundle exec rspec spec/services/principal_matcher_service_spec.rb -e "driving licence"`
Expected: The "exact name + DOB match on a driving licence" test PASSES already (name-only matching incidentally finds it). The "DOB differs (driving licence)" test FAILS: current code only gates DOB-aware filtering on `passport?`, so for `driving_licence` it falls into the `else` branch of `find_exact_match`, matches by name alone (ignoring the DOB mismatch), and wrongly returns `"exact"` instead of falling through to `"fuzzy"`. This is exactly the bug Task 3 fixes.

- [ ] **Step 3: Update PrincipalMatcherService**

Replace:

```ruby
  def find_exact_match
    if passport? && @date_of_birth
      principals.find do |p|
        names_match_exactly?(p.name, @full_name) && p.date_of_birth == @date_of_birth
      end
    else
      principals.find { |p| names_match_exactly?(p.name, @full_name) }
    end
  end
```

with:

```ruby
  def find_exact_match
    if dob_aware_identity? && @date_of_birth
      principals.find do |p|
        names_match_exactly?(p.name, @full_name) && p.date_of_birth == @date_of_birth
      end
    else
      principals.find { |p| names_match_exactly?(p.name, @full_name) }
    end
  end
```

And replace:

```ruby
    if passport?
      principal = create_unconfirmed_principal
      Result.new(principal: principal, match_method: "exact", match_confidence: 1.0)
    else
      Result.new(principal: nil, match_method: nil, match_confidence: nil)
    end
```

with (unchanged behavior, but using a clearer private method name):

```ruby
    if auto_creatable_identity?
      principal = create_unconfirmed_principal
      Result.new(principal: principal, match_method: "exact", match_confidence: 1.0)
    else
      Result.new(principal: nil, match_method: nil, match_confidence: nil)
    end
```

And replace the private `passport?` method with two methods:

```ruby
  def dob_aware_identity?
    Kyc::DocumentCategory.identity?(@document_type)
  end

  def auto_creatable_identity?
    @document_type == PASSPORT_TYPE
  end
```

Update the class doc comment at the top of the file to reflect the split:

```ruby
# Matches an extracted OCR result to an existing KycPrincipal, or creates one.
#
# document_type is the KycDocument's own document_type (e.g. "passport"), passed in
# by the caller — it is document metadata, not part of the extracted result hash.
#
# Identity documents (Kyc::DocumentCategory.identity? — passport, driving_licence):
#   Exact name + DOB match → :exact
#   Jaro-Winkler name similarity >= FUZZY_THRESHOLD → :fuzzy with confidence
#   No match on a passport specifically → creates new unconfirmed KycPrincipal
#   No match on a non-passport identity document → returns nil (left unlinked;
#     auto-creation is deliberately passport-only, see MH-175 design spec)
#
# Proof-of-address / other documents:
#   Fuzzy name match only (no DOB on these documents)
#   No match → returns nil (document left unlinked)
#
# Returns a Result struct with: principal, match_method, match_confidence
```

- [ ] **Step 4: Run the full spec to verify it passes**

Run: `bundle exec rspec spec/services/principal_matcher_service_spec.rb`
Expected: PASS — all examples including the two new ones

- [ ] **Step 5: Commit**

```bash
git add app/services/principal_matcher_service.rb spec/services/principal_matcher_service_spec.rb
git commit -m "MH-175 Extend DOB-aware matching to all identity documents via DocumentCategory"
```

---

### Task 4: ExtractKycDocumentJob uses DocumentCategory and typed extraction data

**Files:**
- Modify: `app/jobs/extract_kyc_document_job.rb`
- Modify: `spec/jobs/extract_kyc_document_job_spec.rb`

This is the task that actually fixes the bank statement bug. The job currently special-cases `document.utility_bill?` and reads `response["account_holder_address_line1"]` directly. After this change it works for any `Kyc::DocumentCategory.proof_of_address?` document type, sourcing fields through the typed schema instead of raw hash keys.

- [ ] **Step 1: Write the failing test for bank account statements**

In `spec/jobs/extract_kyc_document_job_spec.rb`, add a new context after the existing `"when a utility bill is matched to a principal without an address"` context:

```ruby
    context "when a bank account statement is matched to a principal without an address" do
      let(:principal_no_address) do
        create(:kyc_principal, applicant: applicant, name: "Pieter Bakker")
      end

      let(:document) do
        create(:kyc_document, applicant: applicant, document_type: :bank_account_statement, classification_status: :confirmed)
      end

      before do
        principal_no_address
        allow(Kyc::DocumentExtractorService).to receive(:call).and_return(
          "account_holder" => "Pieter Bakker",
          "bank_name" => "ING",
          "account_holder_address_line1" => "Willem Augustinstraat 190",
          "account_holder_city" => "Amsterdam",
          "account_holder_postcode" => "1061 MJ",
          "account_holder_country" => "Netherlands"
        )
      end

      it "matches the principal by account_holder (not full_name)" do
        described_class.new.perform(document.id)
        expect(document.reload.kyc_principal).to eq(principal_no_address)
      end

      it "populates the principal's address from the structured bank statement fields" do
        described_class.new.perform(document.id)
        principal_no_address.reload
        expect(principal_no_address.address_line1).to eq("Willem Augustinstraat 190")
        expect(principal_no_address.city).to eq("Amsterdam")
        expect(principal_no_address.postcode).to eq("1061 MJ")
        expect(principal_no_address.country).to eq("Netherlands")
      end

      it "stores address_match_method and address_match_confidence" do
        described_class.new.perform(document.id)
        document.reload
        expect(document.address_match_method).to eq("exact")
        expect(document.address_match_confidence).to be_present
      end
    end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/jobs/extract_kyc_document_job_spec.rb -e "bank account statement"`
Expected: FAIL — the "matches the principal" test fails because `result["full_name"]` is nil for a bank statement response (it's keyed `account_holder`), so `PrincipalMatcherService` returns no match and the address tests cascade-fail.

- [ ] **Step 3: Update ExtractKycDocumentJob**

Replace `extract_standard`, `populate_address`, and `build_address_string`:

```ruby
  def extract_standard(document)
    response = Kyc::DocumentExtractorService.call(document)
    typed_data = document.extraction_schema.new(response)

    match = PrincipalMatcherService.call(
      applicant: document.applicant,
      document_type: document.document_type,
      result: typed_data.to_matcher_hash
    )

    address_match = if match.principal && Kyc::DocumentCategory.proof_of_address?(document.document_type)
      populate_address(match.principal, typed_data)
      AddressMatcherService.call(
        principal: match.principal,
        extracted_address: address_string(typed_data)
      )
    end

    document.update!(
      status: :complete,
      extracted_data: response,
      kyc_principal: match.principal,
      match_method: match.match_method,
      match_confidence: match.match_confidence,
      address_match_method: address_match&.match_method,
      address_match_confidence: address_match&.match_confidence
    )
  end

  def populate_address(principal, typed_data)
    return if principal.address_line1.present?

    attrs = {
      address_line1: typed_data.structured_address[:line1],
      city: typed_data.structured_address[:city],
      postcode: typed_data.structured_address[:postcode],
      country: typed_data.structured_address[:country]
    }.compact_blank

    return if attrs.empty?

    principal.update!(attrs)
  end

  def address_string(typed_data)
    typed_data.structured_address.values.compact_blank.join(", ")
  end
```

Remove the old `build_address_string` method entirely (replaced by `address_string`).

- [ ] **Step 4: Run the full job spec to verify it passes**

Run: `bundle exec rspec spec/jobs/extract_kyc_document_job_spec.rb`
Expected: PASS — all examples, including the pre-existing utility bill tests (they must still pass unchanged since `UtilityBill#structured_address` produces the same shape `populate_address` expects) and the three new bank statement tests

- [ ] **Step 5: Commit**

```bash
git add app/jobs/extract_kyc_document_job.rb spec/jobs/extract_kyc_document_job_spec.rb
git commit -m "MH-175 Fix bank statement address population via DocumentCategory + typed extraction data"
```

---

### Task 5: UboDocumentRequirements and DocumentCollectionService use the registry

**Files:**
- Modify: `app/services/kyc/compliance/rules/ubo_document_requirements.rb`
- Modify: `app/services/onboarding/document_collection_service.rb`
- Test: `spec/services/kyc/compliance/rules/ubo_document_requirements_spec.rb`
- Test: `spec/services/onboarding/document_collection_service_spec.rb`

- [ ] **Step 1: Write a failing test proving bank statements now satisfy proof_of_address for UBO compliance**

In `spec/services/kyc/compliance/rules/ubo_document_requirements_spec.rb`, find the `it "returns :met when passport and utility bill are present" do ... end` test (inside the `"when the individual is a UBO with a matched principal"` context) and add a sibling test immediately after it:

```ruby
      it "accepts bank account statement as an alternative proof of address" do
        create(:kyc_document, applicant: applicant, kyc_principal: principal, document_type: :passport)
        create(:kyc_document, applicant: applicant, kyc_principal: principal, document_type: :bank_account_statement)

        result = rule.evaluate(entity)

        expect(result).to be_met
        expect(result.satisfied).to contain_exactly("identity", "proof_of_address")
      end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/services/kyc/compliance/rules/ubo_document_requirements_spec.rb`
Expected: FAIL — the new test fails because `ADDRESS_DOC_TYPES` doesn't include `bank_account_statement` yet

- [ ] **Step 3: Update UboDocumentRequirements**

Replace:

```ruby
        IDENTITY_DOC_TYPES = %w[passport driving_licence].freeze
        ADDRESS_DOC_TYPES = %w[utility_bill].freeze
        REQUIRED_CATEGORIES = {
          "identity" => IDENTITY_DOC_TYPES,
          "proof_of_address" => ADDRESS_DOC_TYPES
        }.freeze
```

with:

```ruby
        REQUIRED_CATEGORIES = {
          "identity" => Kyc::DocumentCategory.types_for(:identity),
          "proof_of_address" => Kyc::DocumentCategory.types_for(:proof_of_address)
        }.freeze
```

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bundle exec rspec spec/services/kyc/compliance/rules/ubo_document_requirements_spec.rb`
Expected: PASS — all examples including the new one

- [ ] **Step 5: Update the existing exact-equality assertions, and write a failing test proving bank statements satisfy the checklist**

The existing test `it "creates identity and address items for each declared principal" do ... end` (around line 15) asserts exact equality on the document type lists:

```ruby
        expect(identity_items.first["document_types"]).to eq(%w[passport driving_licence])
        expect(address_items.first["document_types"]).to eq(%w[utility_bill])
```

This will break once the registry includes `government_id` and `bank_account_statement` (Task 1 already added these to `Kyc::DocumentCategory::REGISTRY`). Update these two lines to:

```ruby
        expect(identity_items.first["document_types"]).to eq(Kyc::DocumentCategory.types_for(:identity))
        expect(address_items.first["document_types"]).to eq(Kyc::DocumentCategory.types_for(:proof_of_address))
```

Then, in the same file, find `describe ".all_received?" do` and add a new context after the existing `"when all items received"` context:

```ruby
    context "when proof of address is satisfied by a bank statement instead of a utility bill" do
      let!(:principal) { create(:kyc_principal, applicant: applicant, name: "Person Alpha", source: :applicant_declared) }

      before do
        described_class.generate_checklist(session)
        create(:kyc_document, applicant: applicant, kyc_principal: principal, document_type: :passport)
        create(:kyc_document, applicant: applicant, kyc_principal: principal, document_type: :bank_account_statement)
      end

      it "returns true" do
        expect(described_class.all_received?(session)).to be true
      end
    end
```

- [ ] **Step 6: Run the spec to verify it fails**

Run: `bundle exec rspec spec/services/onboarding/document_collection_service_spec.rb`
Expected: FAIL — the exact-equality assertions fail (registry now includes extra types) and the new bank statement context fails (`ADDRESS_TYPES` doesn't include `bank_account_statement` yet)

- [ ] **Step 7: Update DocumentCollectionService**

Replace:

```ruby
    IDENTITY_TYPES = %w[passport driving_licence].freeze
    ADDRESS_TYPES  = %w[utility_bill].freeze
```

with: (delete these two lines entirely)

Then replace the two usages inside `principal_items`:

```ruby
          {
            "category" => "identity",
            "subject" => principal.name,
            "document_types" => IDENTITY_TYPES,
            "label" => "Proof of identity for #{principal.name}"
          },
          {
            "category" => "proof_of_address",
            "subject" => principal.name,
            "document_types" => ADDRESS_TYPES,
            "label" => "Proof of address for #{principal.name}"
          }
```

with:

```ruby
          {
            "category" => "identity",
            "subject" => principal.name,
            "document_types" => Kyc::DocumentCategory.types_for(:identity),
            "label" => "Proof of identity for #{principal.name}"
          },
          {
            "category" => "proof_of_address",
            "subject" => principal.name,
            "document_types" => Kyc::DocumentCategory.types_for(:proof_of_address),
            "label" => "Proof of address for #{principal.name}"
          }
```

- [ ] **Step 8: Run the spec to verify it passes**

Run: `bundle exec rspec spec/services/onboarding/document_collection_service_spec.rb`
Expected: PASS — all examples including the new one

- [ ] **Step 9: Commit**

```bash
git add app/services/kyc/compliance/rules/ubo_document_requirements.rb \
        app/services/onboarding/document_collection_service.rb \
        spec/services/kyc/compliance/rules/ubo_document_requirements_spec.rb \
        spec/services/onboarding/document_collection_service_spec.rb
git commit -m "MH-175 Replace duplicated document type constants with Kyc::DocumentCategory"
```

---

### Task 6: Full regression run

**Files:** None (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `bundle exec rspec`
Expected: All examples pass, 0 failures

- [ ] **Step 2: Run rubocop**

Run: `bundle exec rubocop app/services/kyc/document_category.rb app/models/extraction_data/ app/jobs/extract_kyc_document_job.rb app/services/principal_matcher_service.rb app/services/kyc/compliance/rules/ubo_document_requirements.rb app/services/onboarding/document_collection_service.rb spec/services/kyc/document_category_spec.rb spec/models/extraction_data/`
Expected: No offenses

- [ ] **Step 3: Run brakeman**

Run: `bundle exec brakeman -q`
Expected: No new warnings

- [ ] **Step 4: Commit if any fixes were needed**

```bash
git add -A
git commit -m "MH-175 Fix lint/regression issues from full suite run"
```

(Only run this step if Step 1-3 required changes. If everything passed cleanly, skip.)

---

### Task 7: Manual verification with the real Jona Kok bank statement

**Files:** None (manual verification only)

This reproduces the originally reported bug end to end, using the same bank statement that surfaced this issue.

- [ ] **Step 1: Confirm in Rails console that the schema accepts the real extracted shape**

```bash
bin/rails runner '
  data = ExtractionData::BankAccountStatement.new(
    account_holder: "Jona Kok",
    bank_name: "ING",
    account_holder_address_line1: "Willem Augustinstraat 190",
    account_holder_city: "Amsterdam",
    account_holder_postcode: "1061 MJ",
    account_holder_country: "Netherlands"
  )
  puts data.person_full_name
  puts data.structured_address.inspect
  puts data.to_matcher_hash.inspect
'
```

Expected output:
```
Jona Kok
{:line1=>"Willem Augustinstraat 190", :city=>"Amsterdam", :postcode=>"1061 MJ", :country=>"Netherlands"}
{"full_name"=>"Jona Kok", "date_of_birth"=>nil}
```

- [ ] **Step 2: Upload the bank statement through the UI against a test applicant with a principal named "Jona Kok" already present, and confirm the principal's address fields populate after extraction completes.**

No code changes in this task — pure verification. If it fails, return to Task 4 and debug before proceeding.
