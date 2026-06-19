# MH-87: Address Matching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract address data from utility bill OCR results and fuzzy-match it against the linked principal's stored address, storing and displaying the result as an informational badge.

**Architecture:** `AddressMatcherService` normalises and Jaro-Winkler compares a raw extracted address string against a principal's concatenated stored address fields. `ProcessKycDocumentJob` calls it after the existing `PrincipalMatcherService` call. Two view partials gain an informational address match badge.

**Tech Stack:** Ruby, JaroWinkler gem (already in Gemfile), Rails, RSpec, FactoryBot

---

## File Map

| Action | File |
|--------|------|
| Create | `db/migrate/TIMESTAMP_add_address_match_to_kyc_documents.rb` |
| Modify | `db/schema.rb` (auto) |
| Create | `app/services/address_matcher_service.rb` |
| Create | `spec/services/address_matcher_service_spec.rb` |
| Modify | `app/jobs/process_kyc_document_job.rb` |
| Modify | `spec/jobs/process_kyc_document_job_spec.rb` |
| Modify | `app/views/kyc_documents/_kyc_document.html.erb` |
| Modify | `app/views/kyc_principals/_document_row.html.erb` |
| Modify | `config/locales/en.yml` |

---

## Task 1: Migration — add address match columns to kyc_documents

**Files:**
- Create: `db/migrate/TIMESTAMP_add_address_match_to_kyc_documents.rb`
- Modify: `db/schema.rb` (auto)

- [ ] **Step 1: Generate migration**

```bash
bin/rails generate migration AddAddressMatchToKycDocuments \
  address_match_method:string \
  address_match_confidence:decimal{4,3}
```

Expected output: `create db/migrate/TIMESTAMP_add_address_match_to_kyc_documents.rb`

- [ ] **Step 2: Run migration**

```bash
bin/rails db:migrate
```

Expected: `== AddAddressMatchToKycDocuments: migrated`

- [ ] **Step 3: Verify schema**

```bash
grep -A 2 "address_match" db/schema.rb
```

Expected output:
```
t.decimal "address_match_confidence", precision: 4, scale: 3
t.string  "address_match_method"
```

- [ ] **Step 4: Commit**

```bash
git add db/migrate/ db/schema.rb
git commit -m "feat: add address_match_method and address_match_confidence to kyc_documents [MH-87]"
```

---

## Task 2: AddressMatcherService — normalise and compare addresses

**Files:**
- Create: `app/services/address_matcher_service.rb`
- Create: `spec/services/address_matcher_service_spec.rb`

The service accepts `principal:` (a `KycPrincipal`) and `extracted_address:` (a String from OCR). It normalises both sides with the same rules — downcase, strip, collapse whitespace, expand common UK abbreviations — then runs `JaroWinkler.distance`. Returns a `Result` struct with `match_method` (String `"exact"`, `"fuzzy"`, or `nil`) and `match_confidence` (Float or `nil`).

**Thresholds:** `>= 0.98` → `"exact"`, `>= 0.80` → `"fuzzy"`, below `0.80` → `nil/nil`.

**Guard conditions — return `Result.new(match_method: nil, match_confidence: nil)` immediately if:**
- `extracted_address` is blank
- the principal has no address fields stored (`address_line1`, `city`, `postcode`, `country` all blank)

- [ ] **Step 1: Write failing specs**

Create `spec/services/address_matcher_service_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AddressMatcherService do
  let(:principal) do
    build(:kyc_principal,
      address_line1: "12 High Street",
      address_line2: nil,
      city:          "London",
      postcode:      "SW1A 1AA",
      country:       "United Kingdom")
  end

  def call(extracted_address)
    described_class.call(principal: principal, extracted_address: extracted_address)
  end

  describe ".call" do
    context "when extracted address is blank" do
      it "returns nil match" do
        result = call(nil)
        expect(result.match_method).to be_nil
        expect(result.match_confidence).to be_nil
      end

      it "returns nil match for empty string" do
        result = call("")
        expect(result.match_method).to be_nil
        expect(result.match_confidence).to be_nil
      end
    end

    context "when principal has no stored address" do
      let(:principal) { build(:kyc_principal, address_line1: nil, address_line2: nil, city: nil, postcode: nil, country: nil) }

      it "returns nil match" do
        result = call("12 High Street, London, SW1A 1AA")
        expect(result.match_method).to be_nil
        expect(result.match_confidence).to be_nil
      end
    end

    context "with an exact match" do
      it "returns exact when strings are identical" do
        result = call("12 High Street, London, SW1A 1AA, United Kingdom")
        expect(result.match_method).to eq("exact")
        expect(result.match_confidence).to eq(1.0)
      end

      it "is case-insensitive" do
        result = call("12 HIGH STREET, LONDON, SW1A 1AA, UNITED KINGDOM")
        expect(result.match_method).to eq("exact")
      end

      it "normalises abbreviations — St → street" do
        result = call("12 High St, London, SW1A 1AA, United Kingdom")
        expect(result.match_method).to eq("exact")
      end

      it "normalises abbreviations — Rd → road" do
        principal2 = build(:kyc_principal,
          address_line1: "5 Oak Road", city: "Manchester", postcode: "M1 1AB", country: "United Kingdom")
        result = described_class.call(principal: principal2, extracted_address: "5 Oak Rd, Manchester, M1 1AB, United Kingdom")
        expect(result.match_method).to eq("exact")
      end
    end

    context "with a fuzzy match" do
      it "returns fuzzy for close but not identical addresses" do
        result = call("12 High Street London SW1A1AA United Kingdom")
        expect(result.match_method).to eq("fuzzy")
        expect(result.match_confidence).to be_between(0.80, 0.98)
      end
    end

    context "with no match" do
      it "returns nil when addresses are clearly different" do
        result = call("99 Fake Road, Manchester, M1 1ZZ, United Kingdom")
        expect(result.match_method).to be_nil
        expect(result.match_confidence).to be_nil
      end
    end
  end
end
```

- [ ] **Step 2: Run specs to confirm they fail**

```bash
bundle exec rspec spec/services/address_matcher_service_spec.rb --format documentation
```

Expected: all examples fail with `uninitialized constant AddressMatcherService`

- [ ] **Step 3: Implement AddressMatcherService**

Create `app/services/address_matcher_service.rb`:

```ruby
# frozen_string_literal: true

class AddressMatcherService
  EXACT_THRESHOLD = 0.98
  FUZZY_THRESHOLD = 0.80

  ABBREVIATIONS = {
    /\bst\b/    => "street",
    /\brd\b/    => "road",
    /\bave?\b/  => "avenue",
    /\bln\b/    => "lane",
    /\bdr\b/    => "drive",
    /\bct\b/    => "court",
    /\bpl\b/    => "place",
    /\bsq\b/    => "square",
    /\bcl\b/    => "close",
    /\buk\b/    => "united kingdom"
  }.freeze

  Result = Data.define(:match_method, :match_confidence)

  def self.call(principal:, extracted_address:)
    new(principal: principal, extracted_address: extracted_address).call
  end

  def initialize(principal:, extracted_address:)
    @principal         = principal
    @extracted_address = extracted_address
  end

  def call
    return no_match if @extracted_address.blank?
    return no_match if principal_address.blank?

    score = JaroWinkler.distance(normalise(@extracted_address), normalise(principal_address))

    if score >= EXACT_THRESHOLD
      Result.new(match_method: "exact", match_confidence: 1.0)
    elsif score >= FUZZY_THRESHOLD
      Result.new(match_method: "fuzzy", match_confidence: score.round(3))
    else
      no_match
    end
  end

  private

  def principal_address
    @principal_address ||= [
      @principal.address_line1,
      @principal.address_line2,
      @principal.city,
      @principal.postcode,
      @principal.country
    ].compact_blank.join(", ")
  end

  def normalise(address)
    result = address.downcase.strip.gsub(/\s+/, " ")
    ABBREVIATIONS.each { |pattern, replacement| result = result.gsub(pattern, replacement) }
    result
  end

  def no_match
    Result.new(match_method: nil, match_confidence: nil)
  end
end
```

- [ ] **Step 4: Run specs to confirm they pass**

```bash
bundle exec rspec spec/services/address_matcher_service_spec.rb --format documentation
```

Expected: all examples pass

- [ ] **Step 5: Commit**

```bash
git add app/services/address_matcher_service.rb spec/services/address_matcher_service_spec.rb
git commit -m "feat: AddressMatcherService — fuzzy address comparison for utility bills [MH-87]"
```

---

## Task 3: Wire AddressMatcherService into ProcessKycDocumentJob

**Files:**
- Modify: `app/jobs/process_kyc_document_job.rb`
- Modify: `spec/jobs/process_kyc_document_job_spec.rb`

Call `AddressMatcherService` after `PrincipalMatcherService`. Only run if the document type is `"utility_bill"`, a principal was matched, and the OCR result includes an `"address"` field.

- [ ] **Step 1: Write failing specs**

Add to `spec/jobs/process_kyc_document_job_spec.rb` inside the `describe "#perform"` block:

```ruby
context "address matching" do
  let(:principal_with_address) do
    create(:kyc_principal,
      applicant:    applicant,
      name:         "Jane Smith",
      address_line1: "12 High Street",
      city:          "London",
      postcode:      "SW1A 1AA",
      country:       "United Kingdom")
  end

  before { principal_with_address }

  context "when document is a utility bill with a matching address" do
    before do
      stub_request(:post, "#{ENV.fetch('KYNETIC_OCR_URL', 'http://localhost:8001')}/process")
        .to_return(
          status: 200,
          body: {
            "full_name"     => "Jane Smith",
            "document_type" => "utility_bill",
            "address"       => "12 High Street, London, SW1A 1AA, United Kingdom"
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "stores address_match_method and address_match_confidence" do
      described_class.new.perform(document.id)
      document.reload
      expect(document.address_match_method).to eq("exact")
      expect(document.address_match_confidence).to be_present
    end
  end

  context "when document is a passport (not a utility bill)" do
    it "does not set address match fields" do
      described_class.new.perform(document.id)
      document.reload
      expect(document.address_match_method).to be_nil
      expect(document.address_match_confidence).to be_nil
    end
  end

  context "when OCR result has no address field" do
    before do
      stub_request(:post, "#{ENV.fetch('KYNETIC_OCR_URL', 'http://localhost:8001')}/process")
        .to_return(
          status: 200,
          body: { "full_name" => "Jane Smith", "document_type" => "utility_bill" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "does not set address match fields" do
      described_class.new.perform(document.id)
      expect(document.reload.address_match_method).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run new specs to confirm they fail**

```bash
bundle exec rspec spec/jobs/process_kyc_document_job_spec.rb --format documentation
```

Expected: the three new address matching examples fail

- [ ] **Step 3: Update ProcessKycDocumentJob**

In `app/jobs/process_kyc_document_job.rb`, replace the `document.update!` call with:

```ruby
def perform(kyc_document_id)
  document = KycDocument.find(kyc_document_id)
  document.processing!
  broadcast_document(document)

  response = ocr_client(document)

  match         = PrincipalMatcherService.call(applicant: document.applicant, result: response)
  address_match = AddressMatcherService.call(
    principal:         match.principal,
    extracted_address: response["address"]
  ) if match.principal && response["document_type"] == "utility_bill"

  document.update!(
    status:                  :complete,
    result:                  response,
    kyc_principal:           match.principal,
    match_method:            match.match_method,
    match_confidence:        match.match_confidence,
    address_match_method:    address_match&.match_method,
    address_match_confidence: address_match&.match_confidence
  )
  broadcast_document(document)
rescue KyneticOcrClient::Error, ClaudeOcrAdapter::Error => e
  document&.update!(status: :error, result: { "error" => e.message })
  broadcast_document(document) if document
end
```

- [ ] **Step 4: Run full job spec to confirm all pass**

```bash
bundle exec rspec spec/jobs/process_kyc_document_job_spec.rb --format documentation
```

Expected: all examples pass

- [ ] **Step 5: Commit**

```bash
git add app/jobs/process_kyc_document_job.rb spec/jobs/process_kyc_document_job_spec.rb
git commit -m "feat: run AddressMatcherService in ProcessKycDocumentJob for utility bills [MH-87]"
```

---

## Task 4: Display address match badges in views + i18n

**Files:**
- Modify: `app/views/kyc_documents/_kyc_document.html.erb`
- Modify: `app/views/kyc_principals/_document_row.html.erb`
- Modify: `config/locales/en.yml`

Add informational badges. Exact → green, fuzzy → yellow. No badge if no match.

- [ ] **Step 1: Add i18n keys**

In `config/locales/en.yml`, inside `kyc_documents:`, add:

```yaml
    address_match_method:
      exact: Address verified
      fuzzy: Address approx. match
```

- [ ] **Step 2: Update `_kyc_document.html.erb` — applicant show page**

In `app/views/kyc_documents/_kyc_document.html.erb`, find the badges block inside the filename sub-div (around line 10–21 where `document.kyc_principal` badges appear). After the existing `unconfirmed?` badge, add:

```erb
<% if document.address_match_method.present? %>
  <span class="inline-flex items-center rounded-full px-1.5 py-0.5 text-xs font-medium
    <%= document.address_match_method == 'exact' ? 'bg-green-100 text-green-700' : 'bg-yellow-100 text-yellow-700' %>">
    <%= t("kyc_documents.address_match_method.#{document.address_match_method}") %>
  </span>
<% end %>
```

- [ ] **Step 3: Update `_document_row.html.erb` — principal show page**

In `app/views/kyc_principals/_document_row.html.erb`, find the `<td>` for the Match column (the one rendering `match_method` badges). After the existing match badge block, add:

```erb
<% if document.address_match_method.present? %>
  <span class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium mt-1
    <%= document.address_match_method == 'exact' ? 'bg-green-100 text-green-700' : 'bg-yellow-100 text-yellow-700' %>">
    <%= t("kyc_documents.address_match_method.#{document.address_match_method}") %>
  </span>
<% end %>
```

- [ ] **Step 4: Run full suite**

```bash
bundle exec rspec
```

Expected: 442+ examples, 0 failures

- [ ] **Step 5: Check i18n**

```bash
bundle exec i18n-tasks missing && bundle exec i18n-tasks unused
```

Expected: no missing, no unused

- [ ] **Step 6: Commit**

```bash
git add app/views/kyc_documents/_kyc_document.html.erb \
        app/views/kyc_principals/_document_row.html.erb \
        config/locales/en.yml
git commit -m "feat: display address match badges on document rows [MH-87]"
```

---

## Final Step: Push and open PR

- [ ] **Push branch and open PR**

```bash
git push -u origin <branch-name>
gh pr create \
  --title "feat: address extraction and matching from utility bills [MH-87]" \
  --body "..."
```
