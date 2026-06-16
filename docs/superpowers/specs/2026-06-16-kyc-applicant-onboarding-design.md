# KYC Applicant Onboarding — Design Spec

**Date:** 2026-06-16
**Status:** Approved
**Deciders:** Stewart Campbell

---

## Context

Before a new merchant can be provisioned in tessera-core they must pass a KYC (Know Your Customer) regulatory check. This Epic introduces the first stage of that process: capturing an **Applicant** (a pre-KYC merchant entity), adding its **Principals** (directors and Persons with Significant Control), and collecting identity/company documents for async OCR processing via the internal `kynetic-ocr` service.

Promotion of an Applicant to a full provisioned Merchant is **out of scope** for this Epic and will be addressed in a future Epic once the human review workflow is designed.

---

## Scope

**In scope:**
- `Applicant` model (STI on `Merchant`)
- `KycPrincipal` model (directors / PSCs belonging to an Applicant)
- `KycDocument` model with optional principal association
- KYC section in sidebar navigation (psp_admin only)
- Applicants index and show pages
- New Applicant form
- Add/edit Principal form on Applicant show page
- Multi-file document upload (Active Storage direct-to-S3, single dropzone)
- `ProcessKycDocumentJob` — async OCR + auto-match document to principal by name
- Turbo Stream document status updates (no polling)

**Out of scope:**
- Promoting an Applicant to a full Merchant / tessera-core provisioning
- Human document review workflow (future Epic)
- Document completeness rules ("each director needs passport + bank statement") — future Epic
- Document result normalisation to discrete columns (TBD — revisit when review workflow is scoped)
- Manual principal–document re-assignment UI (fallback for unmatched docs — future Epic)

---

## Data Model

### STI: `Applicant < Merchant`

A `type` column is added to the `merchants` table. `Applicant` inherits all Merchant columns. The `merchant_id` string field (tessera-core business key) is left null for Applicants — it is only assigned upon successful provisioning, which is out of scope.

The existing `merchant_id` string uniqueness validation on `Merchant` is made conditional (`if: :merchant_id?`) so Applicants, which have no tessera-core ID yet, don't trigger it.

```ruby
class Applicant < Merchant
  has_many :kyc_principals
  has_many :kyc_documents
end
```

### `kyc_principals` table

Represents an individual who must undergo personal KYC as part of the application — a company director, a Person with Significant Control (PSC, 25%+ ownership/voting rights), or both.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `applicant_id` | uuid FK → merchants.id (STI parent table) | |
| `name` | string | Full legal name — used for auto-matching documents |
| `role` | integer (enum) | `director / psc / director_and_psc / shareholder` |
| `email` | string | Optional |
| `created_at` | datetime | |
| `updated_at` | datetime | |

```ruby
class KycPrincipal < ApplicationRecord
  belongs_to :applicant
  has_many :kyc_documents
  enum :role, { director: 0, psc: 1, director_and_psc: 2, shareholder: 3 }
end
```

### `kyc_documents` table

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `applicant_id` | uuid FK → merchants.id (STI parent table) | |
| `kyc_principal_id` | uuid FK → kyc_principals.id, nullable | null = company document; set = individual document |
| `status` | integer (enum) | `pending / processing / complete / error` |
| `result` | jsonb | Full kynetic-ocr response. Shape TBD — may be normalised to discrete columns when human review workflow is designed. |
| `created_at` | datetime | |
| `updated_at` | datetime | |

Active Storage: `KycDocument` has `has_one_attached :file`. Blob stored in S3 (existing Active Storage bucket).

```ruby
class KycDocument < ApplicationRecord
  belongs_to :applicant
  belongs_to :kyc_principal, optional: true
  has_one_attached :file
  enum :status, { pending: 0, processing: 1, complete: 2, error: 3 }
end
```

### Document routing (company vs individual)

| `principal_id` | Document types | Notes |
|---|---|---|
| null | `company_registration`, `utility_bill`, `bank_statement` (company-level) | No `full_name` in OCR response |
| set | `passport`, `driving_licence`, `national_id`, `bank_statement`, `utility_bill` (personal) | `full_name` used for principal auto-match |

### kynetic-ocr API response shape (for reference)

```json
{
  "document_type": "passport | driving_licence | national_id | bank_statement | utility_bill | company_registration | other",
  "full_name": "",
  "date_of_birth": "YYYY-MM-DD",
  "nationality": "",
  "document_number": "",
  "issue_date": "YYYY-MM-DD",
  "expiry_date": "YYYY-MM-DD",
  "address": "",
  "company_name": "",
  "company_registration_number": "",
  "issuing_authority": "",
  "confidence": "high | medium | low",
  "validation_flags": []
}
```

Stored verbatim in `kyc_documents.result` (jsonb).

---

## Navigation

Add a **KYC** group to the sidebar (`_sidebar.html.erb`), visible to `psp_admin` only. The existing "Onboard" link (`new_merchant_path`) is removed.

```
KYC
  Applicants      → /applicants        (ApplicantsController#index)
  New Applicant   → /applicants/new    (ApplicantsController#new)
```

Labels are i18n strings and can be changed without code changes.

---

## Routes

```ruby
resources :applicants, only: %i[new create index show edit update] do
  resources :kyc_principals, only: %i[new create edit update destroy], shallow: true
  resources :kyc_documents, only: %i[create], shallow: true
end
```

---

## Pages

### Applicants index (`/applicants`)

Table of all Applicants: name, company name, country, created date, document count badge. Search by name (same `ILIKE` pattern as Merchants index). Pundit-scoped to psp roles.

### New Applicant (`/applicants/new`)

Form fields: `name`, `company_name`, `contact_email`, `country`. On success, redirects to Applicant show page.

### Applicant show (`/applicants/:id`)

Three sections:

**Profile** — name, company, contact email, country. Editable via `ApplicantsController#edit` / `#update` (same pattern as `MerchantsController#update`).

**Company Documents** — dropzone for company-level documents, list below. Documents where `kyc_principal_id` is null.

**Principals** — one card per `KycPrincipal` showing their name, role, and own document list. Each card has its own upload dropzone. An "Add Principal" link opens the new principal form.

All document rows are Turbo Frames that update in place as OCR results arrive:

```
[icon]  filename    STATUS BADGE    Confidence    Flags
```

Status display:

| Status | Badge | Confidence | Flags |
|---|---|---|---|
| pending | Pending | — | — |
| processing | Processing… | — | — |
| complete | Complete | high / medium / low | list if present |
| error | Error | — | error message |

---

## Document Upload Flow

1. User drags/drops or selects one or more files on a dropzone (Stimulus `dropzone` controller). Dropzones exist at company level and per-principal card — but uploading to any dropzone follows the same path.
2. Active Storage `direct_upload: true` — browser obtains a presigned PUT URL from Rails and uploads each file directly to S3. Puma is not in the upload path.
3. On form submit, a `KycDocument` record is created per file (`status: :pending`, blob attached, `kyc_principal_id` set if uploaded from a principal card).
4. `ProcessKycDocumentJob` is enqueued immediately for each document.

---

## `ProcessKycDocumentJob` (Solid Queue)

After OCR completes, the job attempts to auto-match the document to a `KycPrincipal` by comparing `result["full_name"]` against principal names on the applicant. A match sets `kyc_principal_id` on the document. Unmatched documents (no `full_name`, or no close name match) remain with `kyc_principal_id: nil` — visible in the company documents section and flagged for manual review in a future Epic.

```ruby
class ProcessKycDocumentJob < ApplicationJob
  def perform(kyc_document_id)
    document = KycDocument.find(kyc_document_id)

    document.processing!
    broadcast_document(document)

    response = KyneticOcrClient.process(
      customer_id: document.applicant.id,
      document_key: document.file.key   # S3 key — OCR service uses IAM instance profile
    )

    principal = match_principal(document.applicant, response["full_name"])
    document.update!(status: :complete, result: response, kyc_principal: principal)
    broadcast_document(document)

  rescue => e
    document.update!(status: :error, result: { error: e.message })
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
      locals: { document: }
    )
  end
end
```

The Applicant show page subscribes to the stream:

```erb
<%= turbo_stream_from "applicant_#{@applicant.id}_documents" %>
```

Delivered via Solid Cable (already in stack). No client-side polling required.

---

## `KyneticOcrClient` service

Thin Faraday wrapper around `localhost:8001` (same pattern as `TesseraCoreClient`):

```ruby
module KyneticOcrClient
  BASE_URL = "http://localhost:8001"

  def self.process(customer_id:, document_key:)
    response = connection.post("/process", { customer_id:, document_key: }.to_json)
    JSON.parse(response.body)
  end

  def self.connection
    Faraday.new(BASE_URL) do |f|
      f.headers["Content-Type"] = "application/json"
      f.request :retry, max: 3
    end
  end
end
```

---

## Pundit Policy

`ApplicantPolicy` inherits from `MerchantPolicy`. psp_admin and psp_support can index/show. Only psp_admin can create/edit.

```ruby
class ApplicantPolicy < MerchantPolicy
end

class KycDocumentPolicy < ApplicationPolicy
  # psp_admin only for create
end

class KycPrincipalPolicy < ApplicationPolicy
  # psp_admin only for create/edit/destroy
end
```

---

## Open Decisions

| # | Decision | Status |
|---|---|---|
| 1 | `kyc_documents.result` jsonb vs normalised columns | **TBD** — revisit when human review workflow is designed. Documents are scoped to a single Applicant so cross-org querying is not a near-term requirement. |
| 2 | Validation flag display format | TBD — defer to UI implementation. |
| 3 | Retry/dead-letter strategy for `ProcessKycDocumentJob` | TBD — default Solid Queue retries for now; tune when OCR error patterns are known. |
| 4 | GDPR right-to-erasure | `kyc_documents.result` (jsonb) contains extracted PII (`full_name`, `date_of_birth`, `nationality`, `address`, etc.) and must be explicitly nulled on erasure — deleting the S3 blob alone is insufficient. Erasure path: `doc.file.purge` (removes S3 object + Active Storage rows) + `doc.update!(result: nil)`. A dedicated erasure service/job scoped to an Applicant should be designed before go-live. |
| 5 | Principal auto-match confidence threshold | Currently exact case-insensitive name match. Fuzzy matching (e.g. nicknames, hyphenated names) and confidence thresholds TBD — unmatched docs fall back to `kyc_principal_id: nil` and manual review. |
| 6 | Document completeness rules | Each principal role will eventually require a specific document set (e.g. director: passport + bank statement). Rules engine design deferred to future Epic. |
