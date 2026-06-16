# KYC Applicant Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an Applicant (pre-KYC merchant entity) model with Principals and document upload, async OCR processing via kynetic-ocr, and Turbo Stream status updates.

**Architecture:** Applicant uses STI on the merchants table. KycPrincipal and KycDocument are new models. Documents are uploaded directly to S3 via Active Storage direct upload. ProcessKycDocumentJob calls the kynetic-ocr service and broadcasts Turbo Stream replacements for each document row. The existing "Onboard" sidebar link is replaced with a KYC section.

**Tech Stack:** Rails 8.1, PostgreSQL (uuid PKs), Active Storage (S3), Solid Queue, Turbo Streams / Solid Cable, Stimulus, Pundit, RSpec / FactoryBot / WebMock

**Spec:** `docs/superpowers/specs/2026-06-16-kyc-applicant-onboarding-design.md`

---

## File Map

**New files:**
- `app/models/applicant.rb`
- `app/models/kyc_principal.rb`
- `app/models/kyc_document.rb`
- `app/services/kynetic_ocr_client.rb`
- `app/jobs/process_kyc_document_job.rb`
- `app/controllers/applicants_controller.rb`
- `app/controllers/kyc_principals_controller.rb`
- `app/controllers/kyc_documents_controller.rb`
- `app/policies/applicant_policy.rb`
- `app/policies/kyc_principal_policy.rb`
- `app/policies/kyc_document_policy.rb`
- `app/views/applicants/index.html.erb`
- `app/views/applicants/new.html.erb`
- `app/views/applicants/show.html.erb`
- `app/views/applicants/edit.html.erb`
- `app/views/kyc_principals/new.html.erb`
- `app/views/kyc_principals/edit.html.erb`
- `app/views/kyc_documents/_kyc_document.html.erb`
- `app/views/shared/icons/_kyc.html.erb`
- `app/javascript/controllers/dropzone_controller.js`
- `spec/factories/applicants.rb`
- `spec/factories/kyc_principals.rb`
- `spec/factories/kyc_documents.rb`
- `spec/models/applicant_spec.rb`
- `spec/models/kyc_principal_spec.rb`
- `spec/models/kyc_document_spec.rb`
- `spec/policies/applicant_policy_spec.rb`
- `spec/policies/kyc_principal_policy_spec.rb`
- `spec/policies/kyc_document_policy_spec.rb`
- `spec/services/kynetic_ocr_client_spec.rb`
- `spec/jobs/process_kyc_document_job_spec.rb`
- `spec/requests/applicants_spec.rb`
- `spec/requests/kyc_principals_spec.rb`
- `spec/requests/kyc_documents_spec.rb`

**Modified files:**
- `app/models/merchant.rb` — make `merchant_id` uniqueness validation conditional
- `config/routes.rb` — add applicants, kyc_principals, kyc_documents resources
- `app/views/layouts/_sidebar.html.erb` — replace Onboard link with KYC group
- `config/locales/en.yml` — add KYC i18n keys

---

## Task 1: Migrations

**Files:**
- Create: `db/migrate/*_add_type_to_merchants.rb`
- Create: `db/migrate/*_create_kyc_principals.rb`
- Create: `db/migrate/*_create_kyc_documents.rb`

- [ ] **Step 1: Generate migrations**

```bash
cd tessera-merchant-hub
bin/rails generate migration AddTypeToMerchants type:string
bin/rails generate migration CreateKycPrincipals
bin/rails generate migration CreateKycDocuments
```

- [ ] **Step 2: Edit the kyc_principals migration**

Open the generated `db/migrate/*_create_kyc_principals.rb` and replace its `change` body with:

```ruby
def change
  create_table :kyc_principals, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
    t.references :applicant, type: :uuid, null: false, foreign_key: { to_table: :merchants }
    t.string  :name,  null: false
    t.integer :role,  null: false, default: 0
    t.string  :email
    t.timestamps
  end
end
```

- [ ] **Step 3: Edit the kyc_documents migration**

Open the generated `db/migrate/*_create_kyc_documents.rb` and replace its `change` body with:

```ruby
def change
  create_table :kyc_documents, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
    t.references :applicant,     type: :uuid, null: false, foreign_key: { to_table: :merchants }
    t.references :kyc_principal, type: :uuid, null: true,  foreign_key: true
    t.integer :status, null: false, default: 0
    t.jsonb   :result
    t.timestamps
  end
end
```

- [ ] **Step 4: Run migrations**

```bash
bin/rails db:migrate
```

Expected: three migrations applied, `db/schema.rb` updated with `type` column on merchants, `kyc_principals` table, `kyc_documents` table.

- [ ] **Step 5: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "feat: add migrations for Applicant STI, KycPrincipal, KycDocument"
```

---

## Task 2: Applicant Model

**Files:**
- Create: `app/models/applicant.rb`
- Modify: `app/models/merchant.rb`
- Create: `spec/factories/applicants.rb`
- Create: `spec/models/applicant_spec.rb`

- [ ] **Step 1: Write the failing model spec**

Create `spec/models/applicant_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Applicant, type: :model do
  it "is a subclass of Merchant" do
    expect(described_class.superclass).to eq(Merchant)
  end

  it "does not require merchant_id" do
    applicant = build(:applicant, merchant_id: nil)
    expect(applicant).to be_valid
  end

  it "stores type as Applicant" do
    applicant = create(:applicant)
    expect(Merchant.find(applicant.id).type).to eq("Applicant")
  end

  it { is_expected.to have_many(:kyc_principals) }
  it { is_expected.to have_many(:kyc_documents) }
end
```

- [ ] **Step 2: Run spec to verify it fails**

```bash
bin/rspec spec/models/applicant_spec.rb
```

Expected: fails with `uninitialized constant Applicant`

- [ ] **Step 3: Create the Applicant model**

Create `app/models/applicant.rb`:

```ruby
# frozen_string_literal: true

class Applicant < Merchant
  has_many :kyc_principals, foreign_key: :applicant_id, inverse_of: :applicant, dependent: :destroy
  has_many :kyc_documents,  foreign_key: :applicant_id, inverse_of: :applicant, dependent: :destroy
end
```

- [ ] **Step 4: Make merchant_id validation conditional**

Open `app/models/merchant.rb` and change:

```ruby
validates :merchant_id, presence: true, uniqueness: true
```

to:

```ruby
validates :merchant_id, presence: true, uniqueness: true, if: :merchant_id?
```

- [ ] **Step 5: Create the factory**

Create `spec/factories/applicants.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :applicant do
    name         { "Applicant #{SecureRandom.hex(3)}" }
    company_name { "Co #{SecureRandom.hex(3)} Ltd" }
    country      { "GB" }
  end
end
```

- [ ] **Step 6: Run spec to verify it passes**

```bash
bin/rspec spec/models/applicant_spec.rb
```

Expected: 5 examples, 0 failures

- [ ] **Step 7: Ensure existing merchant specs still pass**

```bash
bin/rspec spec/models/merchant_spec.rb
```

Expected: all pass

- [ ] **Step 8: Commit**

```bash
git add app/models/applicant.rb app/models/merchant.rb spec/models/applicant_spec.rb spec/factories/applicants.rb
git commit -m "feat: add Applicant STI model"
```

---

## Task 3: KycPrincipal Model

**Files:**
- Create: `app/models/kyc_principal.rb`
- Create: `spec/factories/kyc_principals.rb`
- Create: `spec/models/kyc_principal_spec.rb`

- [ ] **Step 1: Write the failing model spec**

Create `spec/models/kyc_principal_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe KycPrincipal, type: :model do
  it { is_expected.to belong_to(:applicant) }
  it { is_expected.to have_many(:kyc_documents) }
  it { is_expected.to validate_presence_of(:name) }

  describe "role enum" do
    it { is_expected.to define_enum_for(:role).with_values(director: 0, psc: 1, director_and_psc: 2, shareholder: 3) }
  end

  it "is valid with minimum attributes" do
    expect(build(:kyc_principal)).to be_valid
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```bash
bin/rspec spec/models/kyc_principal_spec.rb
```

Expected: fails with `uninitialized constant KycPrincipal`

- [ ] **Step 3: Create the model**

Create `app/models/kyc_principal.rb`:

```ruby
# frozen_string_literal: true

class KycPrincipal < ApplicationRecord
  belongs_to :applicant, foreign_key: :applicant_id, inverse_of: :kyc_principals
  has_many :kyc_documents, foreign_key: :kyc_principal_id, inverse_of: :kyc_principal, dependent: :nullify

  enum :role, { director: 0, psc: 1, director_and_psc: 2, shareholder: 3 }, default: :director

  validates :name, presence: true
  validates :role, presence: true
end
```

- [ ] **Step 4: Create the factory**

Create `spec/factories/kyc_principals.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :kyc_principal do
    association :applicant
    name { Faker::Name.name }
    role { :director }
  end
end
```

- [ ] **Step 5: Run spec to verify it passes**

```bash
bin/rspec spec/models/kyc_principal_spec.rb
```

Expected: all pass

- [ ] **Step 6: Commit**

```bash
git add app/models/kyc_principal.rb spec/models/kyc_principal_spec.rb spec/factories/kyc_principals.rb
git commit -m "feat: add KycPrincipal model"
```

---

## Task 4: KycDocument Model

**Files:**
- Create: `app/models/kyc_document.rb`
- Create: `spec/factories/kyc_documents.rb`
- Create: `spec/models/kyc_document_spec.rb`

- [ ] **Step 1: Write the failing model spec**

Create `spec/models/kyc_document_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe KycDocument, type: :model do
  it { is_expected.to belong_to(:applicant) }
  it { is_expected.to belong_to(:kyc_principal).optional }

  describe "status enum" do
    it { is_expected.to define_enum_for(:status).with_values(pending: 0, processing: 1, complete: 2, error: 3) }
  end

  it "defaults to pending status" do
    doc = build(:kyc_document)
    expect(doc.status).to eq("pending")
  end

  it "is valid without a kyc_principal (company document)" do
    expect(build(:kyc_document, kyc_principal: nil)).to be_valid
  end

  it "is valid with a kyc_principal (individual document)" do
    principal = create(:kyc_principal)
    expect(build(:kyc_document, applicant: principal.applicant, kyc_principal: principal)).to be_valid
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```bash
bin/rspec spec/models/kyc_document_spec.rb
```

Expected: fails with `uninitialized constant KycDocument`

- [ ] **Step 3: Create the model**

Create `app/models/kyc_document.rb`:

```ruby
# frozen_string_literal: true

class KycDocument < ApplicationRecord
  belongs_to :applicant,     foreign_key: :applicant_id,     inverse_of: :kyc_documents
  belongs_to :kyc_principal, foreign_key: :kyc_principal_id, inverse_of: :kyc_documents, optional: true

  has_one_attached :file

  enum :status, { pending: 0, processing: 1, complete: 2, error: 3 }, default: :pending
end
```

- [ ] **Step 4: Create the factory**

Create `spec/factories/kyc_documents.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :kyc_document do
    association :applicant
    status { :pending }
  end
end
```

- [ ] **Step 5: Run spec to verify it passes**

```bash
bin/rspec spec/models/kyc_document_spec.rb
```

Expected: all pass

- [ ] **Step 6: Commit**

```bash
git add app/models/kyc_document.rb spec/models/kyc_document_spec.rb spec/factories/kyc_documents.rb
git commit -m "feat: add KycDocument model"
```

---

## Task 5: Policies

**Files:**
- Create: `app/policies/applicant_policy.rb`
- Create: `app/policies/kyc_principal_policy.rb`
- Create: `app/policies/kyc_document_policy.rb`
- Create: `spec/policies/applicant_policy_spec.rb`
- Create: `spec/policies/kyc_principal_policy_spec.rb`
- Create: `spec/policies/kyc_document_policy_spec.rb`

- [ ] **Step 1: Write the failing policy specs**

Create `spec/policies/applicant_policy_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicantPolicy, type: :policy do
  let(:psp_admin)   { build(:user, :psp_admin) }
  let(:psp_support) { build(:user, :psp_support) }
  let(:applicant)   { build(:applicant) }

  describe "index?" do
    it("permits psp_admin")   { expect(described_class.new(psp_admin, applicant).index?).to be true }
    it("permits psp_support") { expect(described_class.new(psp_support, applicant).index?).to be true }
  end

  describe "show?" do
    it("permits psp_admin")   { expect(described_class.new(psp_admin, applicant).show?).to be true }
    it("permits psp_support") { expect(described_class.new(psp_support, applicant).show?).to be true }
  end

  describe "new? / create?" do
    it("permits psp_admin")  { expect(described_class.new(psp_admin, applicant).new?).to be true }
    it("denies psp_support") { expect(described_class.new(psp_support, applicant).new?).to be false }
  end

  describe "edit? / update?" do
    it("permits psp_admin")  { expect(described_class.new(psp_admin, applicant).edit?).to be true }
    it("denies psp_support") { expect(described_class.new(psp_support, applicant).edit?).to be false }
  end

  describe "Scope" do
    before { create(:applicant); create(:applicant) }

    it "psp_admin sees all applicants" do
      scope = ApplicantPolicy::Scope.new(psp_admin, Applicant).resolve
      expect(scope.count).to eq(2)
    end

    it "psp_support sees all applicants" do
      scope = ApplicantPolicy::Scope.new(psp_support, Applicant).resolve
      expect(scope.count).to eq(2)
    end
  end
end
```

Create `spec/policies/kyc_principal_policy_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe KycPrincipalPolicy, type: :policy do
  let(:psp_admin)   { build(:user, :psp_admin) }
  let(:psp_support) { build(:user, :psp_support) }
  let(:principal)   { build(:kyc_principal) }

  it("psp_admin can create")  { expect(described_class.new(psp_admin, principal).create?).to be true }
  it("psp_support cannot create") { expect(described_class.new(psp_support, principal).create?).to be false }
  it("psp_admin can destroy") { expect(described_class.new(psp_admin, principal).destroy?).to be true }
  it("psp_support cannot destroy") { expect(described_class.new(psp_support, principal).destroy?).to be false }
end
```

Create `spec/policies/kyc_document_policy_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe KycDocumentPolicy, type: :policy do
  let(:psp_admin)   { build(:user, :psp_admin) }
  let(:psp_support) { build(:user, :psp_support) }
  let(:document)    { build(:kyc_document) }

  it("psp_admin can create")      { expect(described_class.new(psp_admin, document).create?).to be true }
  it("psp_support cannot create") { expect(described_class.new(psp_support, document).create?).to be false }
end
```

- [ ] **Step 2: Run specs to verify they fail**

```bash
bin/rspec spec/policies/applicant_policy_spec.rb spec/policies/kyc_principal_policy_spec.rb spec/policies/kyc_document_policy_spec.rb
```

Expected: fails with `uninitialized constant ApplicantPolicy`

- [ ] **Step 3: Create the policies**

Create `app/policies/applicant_policy.rb`:

```ruby
# frozen_string_literal: true

class ApplicantPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user.psp_role?
      scope.all
    end
  end

  def index?   = user.psp_role?
  def show?    = user.psp_role?
  def new?     = user.psp_admin?
  def create?  = user.psp_admin?
  def edit?    = user.psp_admin?
  def update?  = user.psp_admin?
end
```

Create `app/policies/kyc_principal_policy.rb`:

```ruby
# frozen_string_literal: true

class KycPrincipalPolicy < ApplicationPolicy
  def create?  = user.psp_admin?
  def edit?    = user.psp_admin?
  def update?  = user.psp_admin?
  def destroy? = user.psp_admin?
end
```

Create `app/policies/kyc_document_policy.rb`:

```ruby
# frozen_string_literal: true

class KycDocumentPolicy < ApplicationPolicy
  def create? = user.psp_admin?
end
```

- [ ] **Step 4: Run specs to verify they pass**

```bash
bin/rspec spec/policies/applicant_policy_spec.rb spec/policies/kyc_principal_policy_spec.rb spec/policies/kyc_document_policy_spec.rb
```

Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add app/policies/applicant_policy.rb app/policies/kyc_principal_policy.rb app/policies/kyc_document_policy.rb \
        spec/policies/applicant_policy_spec.rb spec/policies/kyc_principal_policy_spec.rb spec/policies/kyc_document_policy_spec.rb
git commit -m "feat: add Applicant, KycPrincipal, KycDocument policies"
```

---

## Task 6: KyneticOcrClient Service

**Files:**
- Create: `app/services/kynetic_ocr_client.rb`
- Create: `spec/services/kynetic_ocr_client_spec.rb`

- [ ] **Step 1: Write the failing spec**

Create `spec/services/kynetic_ocr_client_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe KyneticOcrClient do
  let(:base_url) { "http://localhost:8001" }

  describe ".process" do
    let(:customer_id)   { SecureRandom.uuid }
    let(:document_key)  { "uploads/abc123/passport.pdf" }
    let(:response_body) do
      {
        "document_type" => "passport",
        "full_name" => "Jane Smith",
        "date_of_birth" => "1985-03-12",
        "confidence" => "high",
        "validation_flags" => []
      }
    end

    before do
      stub_request(:post, "#{base_url}/process")
        .with(
          body: { customer_id: customer_id, document_key: document_key }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
        .to_return(status: 200, body: response_body.to_json, headers: { "Content-Type" => "application/json" })
    end

    it "returns the parsed JSON response" do
      result = described_class.process(customer_id: customer_id, document_key: document_key)
      expect(result).to eq(response_body)
    end
  end

  describe ".process with error response" do
    let(:customer_id)  { SecureRandom.uuid }
    let(:document_key) { "uploads/bad/file.pdf" }

    before do
      stub_request(:post, "#{base_url}/process")
        .to_return(status: 500, body: "Internal Server Error")
    end

    it "raises an error" do
      expect {
        described_class.process(customer_id: customer_id, document_key: document_key)
      }.to raise_error(KyneticOcrClient::Error)
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```bash
bin/rspec spec/services/kynetic_ocr_client_spec.rb
```

Expected: fails with `uninitialized constant KyneticOcrClient`

- [ ] **Step 3: Create the service**

Create `app/services/kynetic_ocr_client.rb`:

```ruby
# frozen_string_literal: true

require "faraday"
require "json"

class KyneticOcrClient
  class Error < StandardError; end

  BASE_URL = ENV.fetch("KYNETIC_OCR_URL", "http://localhost:8001")

  def self.process(customer_id:, document_key:)
    response = connection.post("/process", { customer_id: customer_id, document_key: document_key }.to_json)
    raise Error, "OCR service error: #{response.status}" unless response.success?
    JSON.parse(response.body)
  rescue Faraday::Error => e
    raise Error, e.message
  end

  def self.connection
    Faraday.new(BASE_URL) do |f|
      f.headers["Content-Type"] = "application/json"
      f.request :retry, max: 3, interval: 0.5, exceptions: [Faraday::ServerError, Faraday::ConnectionFailed]
    end
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

```bash
bin/rspec spec/services/kynetic_ocr_client_spec.rb
```

Expected: 2 examples, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/services/kynetic_ocr_client.rb spec/services/kynetic_ocr_client_spec.rb
git commit -m "feat: add KyneticOcrClient service"
```

---

## Task 7: ProcessKycDocumentJob

**Files:**
- Create: `app/jobs/process_kyc_document_job.rb`
- Create: `spec/jobs/process_kyc_document_job_spec.rb`

- [ ] **Step 1: Write the failing spec**

Create `spec/jobs/process_kyc_document_job_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProcessKycDocumentJob, type: :job do
  let(:applicant)  { create(:applicant) }
  let(:document)   { create(:kyc_document, applicant: applicant) }

  let(:ocr_response) do
    {
      "document_type" => "passport",
      "full_name" => "Jane Smith",
      "confidence" => "high",
      "validation_flags" => []
    }
  end

  before do
    allow(KyneticOcrClient).to receive(:process).and_return(ocr_response)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform" do
    it "transitions document to processing then complete" do
      described_class.perform_now(document.id)
      expect(document.reload.status).to eq("complete")
    end

    it "stores the OCR result on the document" do
      described_class.perform_now(document.id)
      expect(document.reload.result).to eq(ocr_response)
    end

    it "calls KyneticOcrClient with customer_id and document_key" do
      allow(document.file).to receive(:key).and_return("uploads/test/file.pdf")
      expect(KyneticOcrClient).to receive(:process).with(
        customer_id: applicant.id,
        document_key: "uploads/test/file.pdf"
      ).and_return(ocr_response)
      described_class.perform_now(document.id)
    end

    it "broadcasts twice (processing + complete)" do
      described_class.perform_now(document.id)
      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).twice
    end

    context "when OCR raises an error" do
      before { allow(KyneticOcrClient).to receive(:process).and_raise(KyneticOcrClient::Error, "timeout") }

      it "marks the document as error" do
        described_class.perform_now(document.id)
        expect(document.reload.status).to eq("error")
      end

      it "stores the error message in result" do
        described_class.perform_now(document.id)
        expect(document.reload.result).to eq({ "error" => "timeout" })
      end
    end

    context "when full_name matches a principal" do
      let!(:principal) { create(:kyc_principal, applicant: applicant, name: "Jane Smith") }

      it "assigns the matching principal to the document" do
        described_class.perform_now(document.id)
        expect(document.reload.kyc_principal).to eq(principal)
      end
    end

    context "when full_name does not match any principal" do
      it "leaves kyc_principal_id nil" do
        described_class.perform_now(document.id)
        expect(document.reload.kyc_principal).to be_nil
      end
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```bash
bin/rspec spec/jobs/process_kyc_document_job_spec.rb
```

Expected: fails with `uninitialized constant ProcessKycDocumentJob`

- [ ] **Step 3: Create the job**

Create `app/jobs/process_kyc_document_job.rb`:

```ruby
# frozen_string_literal: true

class ProcessKycDocumentJob < ApplicationJob
  queue_as :default

  def perform(kyc_document_id)
    document = KycDocument.find(kyc_document_id)

    document.processing!
    broadcast_document(document)

    response = KyneticOcrClient.process(
      customer_id: document.applicant_id,
      document_key: document.file.key
    )

    principal = match_principal(document.applicant, response["full_name"])
    document.update!(status: :complete, result: response, kyc_principal: principal)
    broadcast_document(document)
  rescue KyneticOcrClient::Error => e
    document.update!(status: :error, result: { "error" => e.message })
    broadcast_document(document)
  end

  private

  def match_principal(applicant, full_name)
    return nil if full_name.blank?
    applicant.kyc_principals.find { |p| p.name.downcase == full_name.downcase }
  end

  def broadcast_document(document)
    Turbo::StreamsChannel.broadcast_replace_to(
      "applicant_#{document.applicant_id}_documents",
      target: "kyc_document_#{document.id}",
      partial: "kyc_documents/kyc_document",
      locals: { document: document }
    )
  end
end
```

- [ ] **Step 4: Run spec to verify it passes**

```bash
bin/rspec spec/jobs/process_kyc_document_job_spec.rb
```

Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add app/jobs/process_kyc_document_job.rb spec/jobs/process_kyc_document_job_spec.rb
git commit -m "feat: add ProcessKycDocumentJob with OCR + principal auto-match"
```

---

## Task 8: Routes

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Add KYC routes**

Open `config/routes.rb` and add after the `resources :merchants` line:

```ruby
resources :applicants, only: %i[new create index show edit update] do
  resources :kyc_principals, only: %i[new create edit update destroy], shallow: true
  resources :kyc_documents,  only: %i[create], shallow: true
end
```

- [ ] **Step 2: Verify routes are generated**

```bash
bin/rails routes | grep -E "applicant|kyc"
```

Expected output includes:
```
applicants          GET    /applicants
new_applicant       GET    /applicants/new
applicant           GET    /applicants/:id
edit_applicant      GET    /applicants/:id/edit
                    PATCH  /applicants/:id
kyc_documents       POST   /applicants/:applicant_id/kyc_documents
kyc_principals      POST   /applicants/:applicant_id/kyc_principals
```

- [ ] **Step 3: Commit**

```bash
git add config/routes.rb
git commit -m "feat: add applicants, kyc_principals, kyc_documents routes"
```

---

## Task 9: ApplicantsController + Views

**Files:**
- Create: `app/controllers/applicants_controller.rb`
- Create: `app/views/applicants/index.html.erb`
- Create: `app/views/applicants/new.html.erb`
- Create: `app/views/applicants/show.html.erb`
- Create: `app/views/applicants/edit.html.erb`
- Create: `app/views/kyc_documents/_kyc_document.html.erb`
- Create: `spec/requests/applicants_spec.rb`

- [ ] **Step 1: Write the failing request spec**

Create `spec/requests/applicants_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Applicants", type: :request do
  let_it_be(:psp_admin)   { create(:user, :psp_admin) }
  let_it_be(:psp_support) { create(:user, :psp_support) }
  let_it_be(:applicant)   { create(:applicant, name: "ACME Widgets") }

  describe "GET /applicants" do
    context "as psp_admin" do
      before { sign_in psp_admin }
      it "returns 200 and lists applicants" do
        get applicants_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("ACME Widgets")
      end
    end

    context "as psp_support" do
      before { sign_in psp_support }
      it "returns 200" do
        get applicants_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "unauthenticated" do
      it "redirects to sign in" do
        get applicants_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "GET /applicants/new" do
    context "as psp_admin" do
      before { sign_in psp_admin }
      it "returns 200" do
        get new_applicant_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "as psp_support" do
      before { sign_in psp_support }
      it "returns 403" do
        get new_applicant_path
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /applicants" do
    context "as psp_admin" do
      before { sign_in psp_admin }

      it "creates an applicant and redirects to show" do
        post applicants_path, params: {
          applicant: { name: "New Corp", company_name: "New Corp Ltd", contact_email: "hello@new.com", country: "GB" }
        }
        expect(response).to redirect_to(applicant_path(Applicant.last))
        expect(Applicant.last.name).to eq("New Corp")
      end

      it "re-renders new with 422 on invalid params" do
        post applicants_path, params: { applicant: { name: "" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "GET /applicants/:id" do
    context "as psp_admin" do
      before { sign_in psp_admin }
      it "returns 200 and shows applicant name" do
        get applicant_path(applicant)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("ACME Widgets")
      end
    end
  end

  describe "PATCH /applicants/:id" do
    context "as psp_admin" do
      before { sign_in psp_admin }

      it "updates and redirects to show" do
        patch applicant_path(applicant), params: {
          applicant: { contact_email: "billing@acme.com" }
        }
        expect(response).to redirect_to(applicant_path(applicant))
        expect(applicant.reload.contact_email).to eq("billing@acme.com")
      end
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```bash
bin/rspec spec/requests/applicants_spec.rb
```

Expected: fails with `uninitialized constant ApplicantsController`

- [ ] **Step 3: Create the controller**

Create `app/controllers/applicants_controller.rb`:

```ruby
# frozen_string_literal: true

class ApplicantsController < ApplicationController
  expose(:applicants) {
    scope = policy_scope(Applicant, policy_scope_class: ApplicantPolicy::Scope)
    if params[:q].present?
      q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
      scope = scope.where("name ILIKE :q OR company_name ILIKE :q", q: q)
    end
    scope.order(:name)
  }

  expose(:applicant) { Applicant.find(params[:id]) }

  def index
    authorize Applicant, :index?, policy_class: ApplicantPolicy
    @pagy, @applicants = pagy(:offset, applicants)
  end

  def show
    authorize applicant, policy_class: ApplicantPolicy
    @principals = applicant.kyc_principals.order(:name)
    @company_documents = applicant.kyc_documents.where(kyc_principal_id: nil).order(:created_at)
  end

  def new
    authorize Applicant, :new?, policy_class: ApplicantPolicy
    @applicant = Applicant.new
  end

  def create
    authorize Applicant, :create?, policy_class: ApplicantPolicy
    @applicant = Applicant.new(applicant_params)
    if @applicant.save
      redirect_to applicant_path(@applicant), notice: t("flash.applicants.create_success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize applicant, policy_class: ApplicantPolicy
  end

  def update
    authorize applicant, policy_class: ApplicantPolicy
    if applicant.update(applicant_update_params)
      redirect_to applicant_path(applicant), notice: t("flash.applicants.update_success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def applicant_params
    params.require(:applicant).permit(:name, :company_name, :contact_email, :country)
  end

  def applicant_update_params
    params.require(:applicant).permit(:contact_email, :country, :company_name)
  end
end
```

- [ ] **Step 4: Create the KycDocument partial**

Create `app/views/kyc_documents/_kyc_document.html.erb`:

```erb
<%= turbo_frame_tag "kyc_document_#{document.id}" do %>
  <div class="flex items-center gap-3 py-2 border-b border-gray-100 last:border-0 text-theme-sm">
    <%# File icon %>
    <svg class="h-4 w-4 shrink-0 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
            d="M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z"/>
    </svg>

    <%# Filename %>
    <span class="flex-1 truncate text-gray-700 font-medium">
      <%= document.file.attached? ? document.file.filename : t("kyc_documents.unnamed") %>
    </span>

    <%# Status badge %>
    <% badge_classes = {
      "pending"    => "bg-gray-100 text-gray-600",
      "processing" => "bg-yellow-100 text-yellow-700",
      "complete"   => "bg-green-100 text-green-700",
      "error"      => "bg-red-100 text-red-700"
    } %>
    <span class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium <%= badge_classes[document.status] %>">
      <%= t("kyc_documents.status.#{document.status}") %>
    </span>

    <%# Confidence (complete only) %>
    <% if document.complete? && document.result.present? %>
      <span class="text-xs text-gray-500 w-12 text-right">
        <%= document.result["confidence"]&.capitalize %>
      </span>
    <% end %>

    <%# Validation flags (complete only) %>
    <% if document.complete? && document.result&.fetch("validation_flags", []).any? %>
      <span class="text-xs text-amber-600">
        <%= document.result["validation_flags"].join(", ") %>
      </span>
    <% end %>

    <%# Error message %>
    <% if document.error? && document.result.present? %>
      <span class="text-xs text-red-600 truncate max-w-xs">
        <%= document.result["error"] %>
      </span>
    <% end %>
  </div>
<% end %>
```

- [ ] **Step 5: Create the applicants index view**

Create `app/views/applicants/index.html.erb`:

```erb
<% content_for :title, t('.page_title') %>

<div class="mb-6 flex items-center justify-between">
  <h1 class="text-xl font-semibold text-gray-900"><%= t('.title') %></h1>
  <% if policy(Applicant).new? %>
    <%= link_to t('.new_applicant'), new_applicant_path, class: "btn-primary text-theme-sm" %>
  <% end %>
</div>

<div class="card">
  <%= form_with url: applicants_path, method: :get,
        data: { controller: "filter", turbo_frame: "applicants-table" },
        class: "mb-4" do %>
    <div class="flex items-center gap-3">
      <div class="relative flex-1 max-w-sm">
        <input type="search" name="q" value="<%= params[:q] %>"
               placeholder="<%= t('.search_placeholder') %>"
               class="form-input pl-9"
               data-action="input->filter#submitDebounced" />
        <span class="pointer-events-none absolute inset-y-0 left-3 flex items-center text-gray-400">
          <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                  d="M21 21l-4.35-4.35M17 11A6 6 0 1 1 5 11a6 6 0 0 1 12 0z"/>
          </svg>
        </span>
      </div>
    </div>
  <% end %>

  <%= turbo_frame_tag "applicants-table" do %>
    <table class="w-full text-left text-theme-sm">
      <thead>
        <tr class="border-b border-gray-200">
          <th class="py-3 pr-4 font-medium text-gray-500 border-r border-gray-100"><%= t('.table.name') %></th>
          <th class="px-4 py-3 font-medium text-gray-500 border-r border-gray-100"><%= t('.table.company') %></th>
          <th class="px-4 py-3 font-medium text-gray-500 border-r border-gray-100"><%= t('.table.country') %></th>
          <th class="px-4 py-3 font-medium text-gray-500 border-r border-gray-100"><%= t('.table.documents') %></th>
          <th class="px-4 py-3 font-medium text-gray-500"><%= t('.table.created') %></th>
        </tr>
      </thead>
      <tbody class="divide-y divide-gray-100">
        <% if @applicants.empty? %>
          <tr>
            <td colspan="5" class="py-10 text-center text-theme-sm text-gray-500"><%= t('.table.empty') %></td>
          </tr>
        <% else %>
          <% @applicants.each do |a| %>
            <tr class="hover:bg-gray-50">
              <td class="py-3 pr-4 font-medium border-r border-gray-100">
                <%= link_to a.name, applicant_path(a), class: "text-brand-600 hover:underline", data: { turbo_frame: "_top" } %>
              </td>
              <td class="px-4 py-3 text-gray-600 border-r border-gray-100"><%= a.company_name.presence || "—" %></td>
              <td class="px-4 py-3 text-gray-600 border-r border-gray-100"><%= a.country.presence || "—" %></td>
              <td class="px-4 py-3 text-gray-600 border-r border-gray-100"><%= a.kyc_documents.size %></td>
              <td class="px-4 py-3 text-gray-500"><%= a.created_at.strftime("%d %b %Y") %></td>
            </tr>
          <% end %>
        <% end %>
      </tbody>
    </table>
    <% if @pagy.pages > 1 %>
      <div class="mt-4 border-t border-gray-200 pt-4"><%== pagy_nav(@pagy) %></div>
    <% end %>
  <% end %>
</div>
```

- [ ] **Step 6: Create the new applicant view**

Create `app/views/applicants/new.html.erb`:

```erb
<% content_for :title, t('.page_title') %>

<div class="mb-4">
  <%= link_to t('.back'), applicants_path, class: "text-theme-sm font-medium text-brand-600 hover:text-brand-700" %>
</div>

<h1 class="text-xl font-semibold text-gray-900 mb-6"><%= t('.title') %></h1>

<div class="card max-w-lg">
  <%= form_with model: @applicant, url: applicants_path do |f| %>
    <%= render "shared/error_messages", object: @applicant %>

    <div class="space-y-4">
      <div>
        <%= f.label :name, t('.fields.name'), class: "block text-theme-sm font-medium text-gray-700 mb-1" %>
        <%= f.text_field :name, class: "form-input w-full", autofocus: true %>
      </div>
      <div>
        <%= f.label :company_name, t('.fields.company_name'), class: "block text-theme-sm font-medium text-gray-700 mb-1" %>
        <%= f.text_field :company_name, class: "form-input w-full" %>
      </div>
      <div>
        <%= f.label :contact_email, t('.fields.contact_email'), class: "block text-theme-sm font-medium text-gray-700 mb-1" %>
        <%= f.email_field :contact_email, class: "form-input w-full" %>
      </div>
      <div>
        <%= f.label :country, t('.fields.country'), class: "block text-theme-sm font-medium text-gray-700 mb-1" %>
        <%= f.text_field :country, class: "form-input w-full", placeholder: "GB" %>
      </div>
    </div>

    <div class="mt-6 flex gap-3">
      <%= f.submit t('.submit'), class: "btn-primary" %>
      <%= link_to t('.cancel'), applicants_path, class: "btn-secondary" %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 7: Create the edit view**

Create `app/views/applicants/edit.html.erb`:

```erb
<% content_for :title, t('.page_title') %>

<div class="mb-4">
  <%= link_to t('.back'), applicant_path(applicant), class: "text-theme-sm font-medium text-brand-600 hover:text-brand-700" %>
</div>

<h1 class="text-xl font-semibold text-gray-900 mb-6"><%= t('.title', name: applicant.name) %></h1>

<div class="card max-w-lg">
  <%= form_with model: applicant, url: applicant_path(applicant), method: :patch do |f| %>
    <%= render "shared/error_messages", object: applicant %>

    <div class="space-y-4">
      <div>
        <%= f.label :contact_email, t('applicants.new.fields.contact_email'), class: "block text-theme-sm font-medium text-gray-700 mb-1" %>
        <%= f.email_field :contact_email, class: "form-input w-full" %>
      </div>
      <div>
        <%= f.label :company_name, t('applicants.new.fields.company_name'), class: "block text-theme-sm font-medium text-gray-700 mb-1" %>
        <%= f.text_field :company_name, class: "form-input w-full" %>
      </div>
      <div>
        <%= f.label :country, t('applicants.new.fields.country'), class: "block text-theme-sm font-medium text-gray-700 mb-1" %>
        <%= f.text_field :country, class: "form-input w-full" %>
      </div>
    </div>

    <div class="mt-6 flex gap-3">
      <%= f.submit t('.submit'), class: "btn-primary" %>
      <%= link_to t('.cancel'), applicant_path(applicant), class: "btn-secondary" %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 8: Create the show view**

Create `app/views/applicants/show.html.erb`:

```erb
<% content_for :title, applicant.name %>

<div class="mb-4">
  <%= link_to t('.back'), applicants_path, class: "text-theme-sm font-medium text-brand-600 hover:text-brand-700" %>
</div>

<div class="mb-6 flex items-start justify-between">
  <div>
    <h1 class="text-xl font-semibold text-gray-900"><%= applicant.name %></h1>
    <p class="mt-0.5 text-theme-sm text-gray-400"><%= applicant.company_name %></p>
  </div>
  <% if policy(applicant).edit? %>
    <%= link_to t('.edit_profile'), edit_applicant_path(applicant), class: "btn-secondary text-theme-sm" %>
  <% end %>
</div>

<%# Subscribe to document status broadcasts %>
<%= turbo_stream_from "applicant_#{applicant.id}_documents" %>

<%# Profile card %>
<div class="card mb-6">
  <h2 class="mb-4 text-xs font-semibold uppercase tracking-wider text-gray-500"><%= t('.sections.profile') %></h2>
  <dl class="grid grid-cols-1 gap-3 sm:grid-cols-2 text-theme-sm">
    <div>
      <dt class="font-medium text-gray-500"><%= t('.fields.contact_email') %></dt>
      <dd class="text-gray-900"><%= applicant.contact_email.presence || "—" %></dd>
    </div>
    <div>
      <dt class="font-medium text-gray-500"><%= t('.fields.country') %></dt>
      <dd class="text-gray-900"><%= applicant.country.presence || "—" %></dd>
    </div>
  </dl>
</div>

<%# Company documents card %>
<div class="card mb-6">
  <div class="flex items-center justify-between mb-4">
    <h2 class="text-xs font-semibold uppercase tracking-wider text-gray-500"><%= t('.sections.company_documents') %></h2>
  </div>

  <% if @company_documents.any? %>
    <div class="mb-4">
      <%= render @company_documents %>
    </div>
  <% end %>

  <% if policy(KycDocument).create? %>
    <%= form_with url: applicant_kyc_documents_path(applicant), data: { controller: "dropzone" } do |f| %>
      <div data-dropzone-target="zone"
           class="border-2 border-dashed border-gray-200 rounded-lg p-6 text-center text-theme-sm text-gray-400
                  hover:border-brand-400 hover:text-brand-600 transition-colors cursor-pointer"
           data-action="dragover->dropzone#dragover dragleave->dropzone#dragleave drop->dropzone#drop">
        <%= f.file_field :files, multiple: true, direct_upload: true,
              class: "sr-only", data: { dropzone_target: "input", action: "change->dropzone#filesSelected" } %>
        <p><%= t('.upload.prompt') %></p>
        <p class="text-xs mt-1"><%= t('.upload.hint') %></p>
      </div>
    <% end %>
  <% end %>
</div>

<%# Principals card %>
<div class="card">
  <div class="flex items-center justify-between mb-4">
    <h2 class="text-xs font-semibold uppercase tracking-wider text-gray-500"><%= t('.sections.principals') %></h2>
    <% if policy(KycPrincipal).create? %>
      <%= link_to t('.add_principal'), new_applicant_kyc_principal_path(applicant),
            class: "text-theme-sm text-brand-600 hover:text-brand-700 font-medium" %>
    <% end %>
  </div>

  <% if @principals.empty? %>
    <p class="text-theme-sm text-gray-400"><%= t('.principals.empty') %></p>
  <% else %>
    <div class="space-y-4">
      <% @principals.each do |principal| %>
        <div class="rounded-lg border border-gray-100 bg-gray-50 p-4">
          <div class="flex items-center justify-between mb-3">
            <div>
              <span class="font-medium text-gray-900 text-theme-sm"><%= principal.name %></span>
              <span class="ml-2 text-xs text-gray-500">· <%= t("kyc_principals.roles.#{principal.role}") %></span>
            </div>
            <% if policy(principal).edit? %>
              <%= link_to t('.principals.edit'), edit_kyc_principal_path(principal),
                    class: "text-xs text-gray-500 hover:text-gray-700" %>
            <% end %>
          </div>

          <% principal_docs = principal.kyc_documents.order(:created_at) %>
          <% if principal_docs.any? %>
            <div class="mb-3">
              <%= render principal_docs %>
            </div>
          <% end %>

          <% if policy(KycDocument).create? %>
            <%= form_with url: applicant_kyc_documents_path(applicant),
                  data: { controller: "dropzone" } do |f| %>
              <%= f.hidden_field :kyc_principal_id, value: principal.id %>
              <div data-dropzone-target="zone"
                   class="border border-dashed border-gray-300 rounded p-3 text-center text-xs text-gray-400
                          hover:border-brand-400 hover:text-brand-500 transition-colors cursor-pointer"
                   data-action="dragover->dropzone#dragover dragleave->dropzone#dragleave drop->dropzone#drop">
                <%= f.file_field :files, multiple: true, direct_upload: true,
                      class: "sr-only", data: { dropzone_target: "input", action: "change->dropzone#filesSelected" } %>
                <p><%= t('.upload.prompt_for', name: principal.name) %></p>
              </div>
            <% end %>
          <% end %>
        </div>
      <% end %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 9: Run the request spec to verify it passes**

```bash
bin/rspec spec/requests/applicants_spec.rb
```

Expected: all pass

- [ ] **Step 10: Commit**

```bash
git add app/controllers/applicants_controller.rb \
        app/views/applicants/ \
        app/views/kyc_documents/ \
        spec/requests/applicants_spec.rb
git commit -m "feat: add ApplicantsController and views"
```

---

## Task 10: KycPrincipalsController + Views

**Files:**
- Create: `app/controllers/kyc_principals_controller.rb`
- Create: `app/views/kyc_principals/new.html.erb`
- Create: `app/views/kyc_principals/edit.html.erb`
- Create: `spec/requests/kyc_principals_spec.rb`

- [ ] **Step 1: Write the failing request spec**

Create `spec/requests/kyc_principals_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "KycPrincipals", type: :request do
  let_it_be(:psp_admin)   { create(:user, :psp_admin) }
  let_it_be(:psp_support) { create(:user, :psp_support) }
  let_it_be(:applicant)   { create(:applicant) }

  describe "GET /applicants/:applicant_id/kyc_principals/new" do
    context "as psp_admin" do
      before { sign_in psp_admin }
      it "returns 200" do
        get new_applicant_kyc_principal_path(applicant)
        expect(response).to have_http_status(:ok)
      end
    end

    context "as psp_support" do
      before { sign_in psp_support }
      it "returns 403" do
        get new_applicant_kyc_principal_path(applicant)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /applicants/:applicant_id/kyc_principals" do
    context "as psp_admin" do
      before { sign_in psp_admin }

      it "creates principal and redirects to applicant show" do
        post applicant_kyc_principals_path(applicant), params: {
          kyc_principal: { name: "Jane Smith", role: "director" }
        }
        expect(response).to redirect_to(applicant_path(applicant))
        expect(applicant.kyc_principals.last.name).to eq("Jane Smith")
      end

      it "re-renders new with 422 on blank name" do
        post applicant_kyc_principals_path(applicant), params: {
          kyc_principal: { name: "", role: "director" }
        }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "PATCH /kyc_principals/:id" do
    let_it_be(:principal) { create(:kyc_principal, applicant: applicant, name: "Old Name") }

    context "as psp_admin" do
      before { sign_in psp_admin }

      it "updates and redirects to applicant show" do
        patch kyc_principal_path(principal), params: {
          kyc_principal: { name: "New Name" }
        }
        expect(response).to redirect_to(applicant_path(applicant))
        expect(principal.reload.name).to eq("New Name")
      end
    end
  end

  describe "DELETE /kyc_principals/:id" do
    let!(:principal) { create(:kyc_principal, applicant: applicant) }

    context "as psp_admin" do
      before { sign_in psp_admin }

      it "destroys and redirects to applicant show" do
        delete kyc_principal_path(principal)
        expect(response).to redirect_to(applicant_path(applicant))
        expect(KycPrincipal.find_by(id: principal.id)).to be_nil
      end
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```bash
bin/rspec spec/requests/kyc_principals_spec.rb
```

Expected: fails with `uninitialized constant KycPrincipalsController`

- [ ] **Step 3: Create the controller**

Create `app/controllers/kyc_principals_controller.rb`:

```ruby
# frozen_string_literal: true

class KycPrincipalsController < ApplicationController
  before_action :set_applicant, only: %i[new create]
  before_action :set_principal, only: %i[edit update destroy]

  def new
    @principal = @applicant.kyc_principals.build
    authorize @principal, policy_class: KycPrincipalPolicy
  end

  def create
    @principal = @applicant.kyc_principals.build(principal_params)
    authorize @principal, policy_class: KycPrincipalPolicy
    if @principal.save
      redirect_to applicant_path(@applicant), notice: t("flash.kyc_principals.create_success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @principal, policy_class: KycPrincipalPolicy
  end

  def update
    authorize @principal, policy_class: KycPrincipalPolicy
    if @principal.update(principal_params)
      redirect_to applicant_path(@principal.applicant), notice: t("flash.kyc_principals.update_success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @principal, policy_class: KycPrincipalPolicy
    applicant = @principal.applicant
    @principal.destroy!
    redirect_to applicant_path(applicant), notice: t("flash.kyc_principals.destroy_success")
  end

  private

  def set_applicant
    @applicant = Applicant.find(params[:applicant_id])
  end

  def set_principal
    @principal = KycPrincipal.find(params[:id])
  end

  def principal_params
    params.require(:kyc_principal).permit(:name, :role, :email)
  end
end
```

- [ ] **Step 4: Create the new principal view**

Create `app/views/kyc_principals/new.html.erb`:

```erb
<% content_for :title, t('.page_title') %>

<div class="mb-4">
  <%= link_to t('.back'), applicant_path(@applicant), class: "text-theme-sm font-medium text-brand-600 hover:text-brand-700" %>
</div>

<h1 class="text-xl font-semibold text-gray-900 mb-6"><%= t('.title') %></h1>

<div class="card max-w-lg">
  <%= form_with model: [@applicant, @principal], url: applicant_kyc_principals_path(@applicant) do |f| %>
    <%= render "shared/error_messages", object: @principal %>

    <div class="space-y-4">
      <div>
        <%= f.label :name, t('.fields.name'), class: "block text-theme-sm font-medium text-gray-700 mb-1" %>
        <%= f.text_field :name, class: "form-input w-full", autofocus: true %>
      </div>
      <div>
        <%= f.label :role, t('.fields.role'), class: "block text-theme-sm font-medium text-gray-700 mb-1" %>
        <%= f.select :role, KycPrincipal.roles.keys.map { |r| [t("kyc_principals.roles.#{r}"), r] },
              {}, class: "form-input w-full" %>
      </div>
      <div>
        <%= f.label :email, t('.fields.email'), class: "block text-theme-sm font-medium text-gray-700 mb-1" %>
        <%= f.email_field :email, class: "form-input w-full" %>
      </div>
    </div>

    <div class="mt-6 flex gap-3">
      <%= f.submit t('.submit'), class: "btn-primary" %>
      <%= link_to t('.cancel'), applicant_path(@applicant), class: "btn-secondary" %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 5: Create the edit principal view**

Create `app/views/kyc_principals/edit.html.erb`:

```erb
<% content_for :title, t('.page_title') %>

<div class="mb-4">
  <%= link_to t('.back'), applicant_path(@principal.applicant), class: "text-theme-sm font-medium text-brand-600 hover:text-brand-700" %>
</div>

<h1 class="text-xl font-semibold text-gray-900 mb-6"><%= t('.title', name: @principal.name) %></h1>

<div class="card max-w-lg">
  <%= form_with model: @principal, url: kyc_principal_path(@principal), method: :patch do |f| %>
    <%= render "shared/error_messages", object: @principal %>

    <div class="space-y-4">
      <div>
        <%= f.label :name, t('kyc_principals.new.fields.name'), class: "block text-theme-sm font-medium text-gray-700 mb-1" %>
        <%= f.text_field :name, class: "form-input w-full" %>
      </div>
      <div>
        <%= f.label :role, t('kyc_principals.new.fields.role'), class: "block text-theme-sm font-medium text-gray-700 mb-1" %>
        <%= f.select :role, KycPrincipal.roles.keys.map { |r| [t("kyc_principals.roles.#{r}"), r] },
              {}, class: "form-input w-full" %>
      </div>
      <div>
        <%= f.label :email, t('kyc_principals.new.fields.email'), class: "block text-theme-sm font-medium text-gray-700 mb-1" %>
        <%= f.email_field :email, class: "form-input w-full" %>
      </div>
    </div>

    <div class="mt-6 flex gap-3">
      <%= f.submit t('.submit'), class: "btn-primary" %>
      <%= link_to t('.cancel'), applicant_path(@principal.applicant), class: "btn-secondary" %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 6: Run spec to verify it passes**

```bash
bin/rspec spec/requests/kyc_principals_spec.rb
```

Expected: all pass

- [ ] **Step 7: Commit**

```bash
git add app/controllers/kyc_principals_controller.rb app/views/kyc_principals/ spec/requests/kyc_principals_spec.rb
git commit -m "feat: add KycPrincipalsController and views"
```

---

## Task 11: KycDocumentsController

**Files:**
- Create: `app/controllers/kyc_documents_controller.rb`
- Create: `spec/requests/kyc_documents_spec.rb`

- [ ] **Step 1: Write the failing request spec**

Create `spec/requests/kyc_documents_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "KycDocuments", type: :request do
  let_it_be(:psp_admin)   { create(:user, :psp_admin) }
  let_it_be(:psp_support) { create(:user, :psp_support) }
  let_it_be(:applicant)   { create(:applicant) }

  describe "POST /applicants/:applicant_id/kyc_documents" do
    context "as psp_admin" do
      before { sign_in psp_admin }

      it "creates a KycDocument and enqueues the job" do
        file = fixture_file_upload(Rails.root.join("spec/fixtures/files/sample.pdf"), "application/pdf")
        expect {
          post applicant_kyc_documents_path(applicant), params: { files: [file] }
        }.to have_enqueued_job(ProcessKycDocumentJob)
        expect(response).to redirect_to(applicant_path(applicant))
      end
    end

    context "as psp_support" do
      before { sign_in psp_support }

      it "returns 403" do
        post applicant_kyc_documents_path(applicant), params: { files: [] }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
```

- [ ] **Step 2: Create a fixture file for the spec**

```bash
mkdir -p spec/fixtures/files
dd if=/dev/urandom bs=1024 count=4 2>/dev/null | base64 > spec/fixtures/files/sample.pdf
```

- [ ] **Step 3: Run spec to verify it fails**

```bash
bin/rspec spec/requests/kyc_documents_spec.rb
```

Expected: fails with `uninitialized constant KycDocumentsController`

- [ ] **Step 4: Create the controller**

Create `app/controllers/kyc_documents_controller.rb`:

```ruby
# frozen_string_literal: true

class KycDocumentsController < ApplicationController
  before_action :set_applicant

  def create
    authorize KycDocument, policy_class: KycDocumentPolicy

    files = Array(params[:files])
    files.each do |file|
      document = @applicant.kyc_documents.build(kyc_principal_id: params[:kyc_principal_id])
      document.file.attach(file)
      document.save!
      ProcessKycDocumentJob.perform_later(document.id)
    end

    redirect_to applicant_path(@applicant), notice: t("flash.kyc_documents.upload_success", count: files.size)
  end

  private

  def set_applicant
    @applicant = Applicant.find(params[:applicant_id])
  end
end
```

- [ ] **Step 5: Run spec to verify it passes**

```bash
bin/rspec spec/requests/kyc_documents_spec.rb
```

Expected: all pass

- [ ] **Step 6: Commit**

```bash
git add app/controllers/kyc_documents_controller.rb spec/requests/kyc_documents_spec.rb spec/fixtures/
git commit -m "feat: add KycDocumentsController"
```

---

## Task 12: Dropzone Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/dropzone_controller.js`

- [ ] **Step 1: Create the Stimulus controller**

Create `app/javascript/controllers/dropzone_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"

export default class extends Controller {
  static targets = ["zone", "input"]

  dragover(event) {
    event.preventDefault()
    this.zoneTarget.classList.add("border-brand-400", "bg-brand-50")
  }

  dragleave() {
    this.zoneTarget.classList.remove("border-brand-400", "bg-brand-50")
  }

  drop(event) {
    event.preventDefault()
    this.zoneTarget.classList.remove("border-brand-400", "bg-brand-50")
    this.uploadFiles(event.dataTransfer.files)
  }

  filesSelected(event) {
    this.uploadFiles(event.target.files)
  }

  // Opens the file picker when the zone is clicked
  connect() {
    this.zoneTarget.addEventListener("click", () => this.inputTarget.click())
  }

  uploadFiles(files) {
    Array.from(files).forEach(file => this.uploadFile(file))
  }

  uploadFile(file) {
    const url = this.inputTarget.dataset.directUploadUrl
    const upload = new DirectUpload(file, url)
    upload.create((error, blob) => {
      if (error) {
        console.error("Upload failed:", error)
      } else {
        const hiddenField = document.createElement("input")
        hiddenField.setAttribute("type", "hidden")
        hiddenField.setAttribute("name", "files[]")
        hiddenField.setAttribute("value", blob.signed_id)
        this.element.appendChild(hiddenField)
        this.element.requestSubmit()
      }
    })
  }
}
```

- [ ] **Step 2: Register the controller**

Open `app/javascript/controllers/index.js` and add:

```javascript
import DropzoneController from "./dropzone_controller"
application.register("dropzone", DropzoneController)
```

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/dropzone_controller.js app/javascript/controllers/index.js
git commit -m "feat: add Stimulus dropzone controller for direct S3 upload"
```

---

## Task 13: Sidebar Navigation + i18n

**Files:**
- Modify: `app/views/layouts/_sidebar.html.erb`
- Create: `app/views/shared/icons/_kyc.html.erb`
- Modify: `config/locales/en.yml`

- [ ] **Step 1: Add the KYC icon partial**

Create `app/views/shared/icons/_kyc.html.erb`:

```erb
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"
     stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"
     class="<%= local_assigns[:class] || 'h-5 w-5' %>" aria-hidden="true">
  <path d="M9 12.75L11.25 15 15 9.75m-3-7.036A11.959 11.959 0 013.598 6 11.99 11.99 0 003 9.749c0 5.592 3.824 10.29 9 11.623 5.176-1.332 9-6.03 9-11.622 0-1.31-.21-2.571-.598-3.751h-.152c-3.196 0-6.1-1.248-8.25-3.285z"/>
</svg>
```

- [ ] **Step 2: Update the sidebar**

Open `app/views/layouts/_sidebar.html.erb`. Find the PSP role navigation block and replace the existing "Onboard" link:

```erb
<% if current_user.psp_admin? %>
  <%= nav_link_to t('layouts.navigation.onboard'), new_merchant_path, controller: "merchants", icon: :onboard %>
<% end %>
```

with the KYC group:

```erb
<% if current_user.psp_admin? %>
  <p class="sidebar-group-title mt-4 mb-2 px-3 text-xs font-semibold uppercase tracking-wider text-gray-500">
    <%= t('layouts.navigation.kyc') %>
  </p>
  <%= nav_link_to t('layouts.navigation.applicants'), applicants_path, controller: "applicants", icon: :kyc %>
  <%= nav_link_to t('layouts.navigation.new_applicant'), new_applicant_path, controller: "applicants", icon: :kyc %>
<% end %>
```

Also remove the matching Onboard link from the mobile drawer section further down the file.

- [ ] **Step 3: Add i18n keys**

Open `config/locales/en.yml` and add the following under the `en:` key. Find the `layouts:` section and add:

```yaml
      kyc: "KYC"
      applicants: "Applicants"
      new_applicant: "New Applicant"
```

Then add top-level sections for the new controllers and models:

```yaml
  flash:
    applicants:
      create_success: "Applicant created successfully."
      update_success: "Applicant updated."
    kyc_principals:
      create_success: "Principal added."
      update_success: "Principal updated."
      destroy_success: "Principal removed."
    kyc_documents:
      upload_success:
        one: "1 document uploaded."
        other: "%{count} documents uploaded."

  kyc_documents:
    unnamed: "Unnamed document"
    status:
      pending: "Pending"
      processing: "Processing…"
      complete: "Complete"
      error: "Error"

  kyc_principals:
    roles:
      director: "Director"
      psc: "PSC"
      director_and_psc: "Director & PSC"
      shareholder: "Shareholder"

  applicants:
    new:
      page_title: "New Applicant"
      title: "Add Applicant"
      back: "← Back to Applicants"
      submit: "Create Applicant"
      cancel: "Cancel"
      fields:
        name: "Trading name"
        company_name: "Legal company name"
        contact_email: "Contact email"
        country: "Country code (e.g. GB)"
    edit:
      page_title: "Edit Applicant"
      title: "Edit %{name}"
      back: "← Back"
      submit: "Save changes"
      cancel: "Cancel"
    show:
      back: "← Back to Applicants"
      edit_profile: "Edit profile"
      add_principal: "Add Principal"
      sections:
        profile: "Profile"
        company_documents: "Company Documents"
        principals: "Principals"
      fields:
        contact_email: "Contact email"
        country: "Country"
      principals:
        empty: "No principals added yet."
        edit: "Edit"
      upload:
        prompt: "Drop files here or click to browse"
        hint: "Passports, bank statements, utility bills, company docs"
        prompt_for: "Upload document for %{name}"
    index:
      page_title: "Applicants"
      title: "Applicants"
      new_applicant: "New Applicant"
      search_placeholder: "Search by name or company…"
      table:
        name: "Name"
        company: "Company"
        country: "Country"
        documents: "Docs"
        created: "Created"
        empty: "No applicants yet."

  kyc_principals:
    roles:
      director: "Director"
      psc: "PSC"
      director_and_psc: "Director & PSC"
      shareholder: "Shareholder"
    new:
      page_title: "Add Principal"
      title: "Add Principal"
      back: "← Back"
      submit: "Add Principal"
      cancel: "Cancel"
      fields:
        name: "Full legal name"
        role: "Role"
        email: "Email (optional)"
    edit:
      page_title: "Edit Principal"
      title: "Edit %{name}"
      submit: "Save changes"
      cancel: "Cancel"
```

- [ ] **Step 4: Run i18n-tasks to verify no missing/unused keys**

```bash
bin/rails runner "require 'i18n/tasks'; I18nTasks::Commands.new.health"
```

Or via rake:

```bash
bundle exec i18n-tasks health
```

Expected: no missing or unused keys reported (fix any flagged)

- [ ] **Step 5: Run the full test suite**

```bash
bin/rspec
```

Expected: all pass

- [ ] **Step 6: Commit**

```bash
git add app/views/layouts/_sidebar.html.erb app/views/shared/icons/_kyc.html.erb config/locales/en.yml
git commit -m "feat: add KYC sidebar navigation and i18n strings"
```

---

## Self-Review

**Spec coverage:**
- ✅ Applicant STI model → Task 2
- ✅ KycPrincipal model → Task 3
- ✅ KycDocument model → Task 4
- ✅ Policies → Task 5
- ✅ KyneticOcrClient → Task 6
- ✅ ProcessKycDocumentJob + auto-match → Task 7
- ✅ Routes → Task 8
- ✅ Applicants CRUD → Task 9
- ✅ KycPrincipals CRUD → Task 10
- ✅ KycDocuments create → Task 11
- ✅ Dropzone Stimulus controller → Task 12
- ✅ Sidebar KYC section → Task 13
- ✅ i18n strings → Task 13
- ✅ Turbo Stream subscription in show view → Task 9 (show.html.erb)
- ✅ Turbo Frame on document partial → Task 9 (_kyc_document.html.erb)
- ✅ GDPR noted as open decision — no code required in this Epic

**Out of scope confirmed (no tasks needed):**
- Promoting Applicant to Merchant
- Human review workflow
- Document completeness rules
- Manual principal re-assignment for unmatched docs
