# ADR-010: KYC Onboarding Chatbot

- **Status:** **Proposed**
- **Date:** 2026-06-25
- **Deciders:** Stewart Campbell _(confirm)_

## Context

Applicant KYC onboarding is currently admin-driven: documents are uploaded, classified, extracted, and reviewed within the Merchant Hub admin UI. The applicant has no self-service capability — all data arrives via documents, and any pre-application communication happens outside the platform (email, phone, forms).

We want to offer applicants a conversational self-service front door that:

1. Collects structured data (company details, directors, UBOs, ownership, business activity, jurisdictions) before documents arrive
2. Generates a tailored document checklist from the compliance rules engine
3. Accepts and validates documents inline — classifying, extracting, and cross-referencing against declared data
4. Feeds into the existing admin pipeline — same models, same compliance assessment

The chatbot is an **alternative route**, not a replacement. The existing admin-driven flow remains fully functional.

## Decisions

### 1. Conversation model: Structured state machine with AI polish

The conversation flow is driven by a deterministic 6-stage state machine. Claude handles natural language — phrasing questions, extracting structured data from free-text answers, and asking follow-ups — but cannot skip stages or bypass validation. Stage transitions are validated server-side.

**Alternatives considered:**

| Approach | Pros | Cons |
|----------|------|------|
| **Fully AI-driven** — Claude manages entire flow via system prompt | Most flexible, handles edge cases naturally | Unpredictable for compliance, hard to audit, risk of missing required fields |
| **Hybrid AI with guardrails** — Claude drives but must hit checkpoints | More natural than pure state machine | More complex than state machine, marginal benefit for structured data collection |
| **Structured state machine** _(chosen)_ | Most auditable, deterministic, testable | Less flexible for unexpected applicant questions |

**Rationale:** Every piece of collected data traces to a defined stage with known validation rules. Claude adds conversational quality without introducing non-determinism. Compliance teams can audit the data collection flow because the stages and required fields are code, not prompts.

### 2. Data model: Same models with `source` enum

Declared data is stored in the existing `KycPrincipal`, `Kyc::CorporateEntity`, and `Kyc::OwnershipEdge` models with a `source` enum distinguishing `applicant_declared` from `document_extracted`.

**Alternatives considered:**

| Approach | Pros | Cons |
|----------|------|------|
| **JSONB on conversation session** | Clean separation, simple to start | Can't run compliance rules on declared data, duplicate rendering logic, reconciliation step needed |
| **Separate staging models** | Cleanest separation, no risk of mixing | Significant model duplication, lots of mapping code, higher maintenance |
| **Same models + source enum** _(chosen)_ | Compliance rules work immediately, cross-reference service already compares sources, minimal addition | Must handle reconciliation when both declared and extracted records exist for the same entity |

**Rationale:** Reusing existing models means the compliance rules engine generates the document checklist from declared data with zero new logic. The cross-reference service already compares data sources. Reconciliation (matching declared to extracted records) is a bounded problem solvable with the existing name-matching infrastructure.

### 3. Hosting: Public page on Merchant Hub, designed for extraction

The chatbot is built as a public-facing section of the existing Rails app. The conversation engine, state machine, and data capture logic sit behind a clean service boundary so the chatbot can be extracted into a standalone service later.

**What this means in practice:**

- Separate controller namespace (`Onboarding::`)
- No direct model access from controllers — all interaction through service objects
- Conversation engine has a defined interface that could become an API
- Chat UI is a self-contained Stimulus controller

**Rationale:** Building in the Hub is fastest for proof of concept. The service boundary ensures extraction is a deployment change, not a rewrite.

### 4. Applicant authentication: Separate account

Applicants create their own account (email + password) in a separate auth scope from admin users. This is a new user type — not a PSP admin or support user.

**Implementation options (to be decided during planning):**

- Devise with a separate `ApplicantUser` model
- Devise scope on the existing User model with a role
- Simple email/password auth without Devise

Minimal for v1 — email verification, password reset, session management. No OAuth or SSO.

## Conversation Stages

Six stages, executed sequentially. Applicant can resume across sessions.

### Stage 1: Company Information

| Field | Type | Required |
|-------|------|----------|
| company_name | string | yes |
| registration_number | string | yes |
| company_type | string | yes |
| registered_address | string | yes |
| country_of_incorporation | string | yes |

**Creates:** `Kyc::CorporateEntity` (entity_type: corporate, source: applicant_declared)

### Stage 2: Directors & UBOs

| Field | Type | Required |
|-------|------|----------|
| full_name | string | yes |
| date_of_birth | date | yes |
| nationality | string | yes |
| role | string | yes (director / shareholder / both) |
| residential_address | string | no |

**Loops:** Bot asks "Are there any more directors or shareholders?" — yes loops, no advances.

**Creates:** `KycPrincipal` (source: applicant_declared) + `Kyc::CorporateEntity` (entity_type: individual, source: applicant_declared) per person.

### Stage 3: Ownership Structure

| Field | Type | Required |
|-------|------|----------|
| owner (entity ref) | reference | yes |
| owned entity (entity ref) | reference | yes |
| percentage | decimal | yes for equity |
| relationship_type | string | yes (equity / nominee / contractual) |

**Loops:** Per entity pair. Bot walks through: "What percentage of [Company] does [Person] own?"

**Creates:** `Kyc::OwnershipEdge` (source: applicant_declared)

**Validation:** Bot flags if percentages don't sum to 100% and asks for clarification.

### Stage 4: Business Activity

| Field | Type | Required |
|-------|------|----------|
| industry | string | yes |
| business_description | string | yes |
| website | string | no |
| expected_monthly_volume | string | no |
| expected_transaction_count | string | no |

**Stores:** JSONB on `OnboardingSession.stage_data` (no existing model for business activity data).

### Stage 5: Jurisdictions

| Field | Type | Required |
|-------|------|----------|
| country | string | yes |
| licence_type | string | no |
| licence_number | string | no |

**Loops:** "Does the company operate in any other countries?"

**Stores:** JSONB on `OnboardingSession.stage_data`.

### Stage 6: Document Collection

Computed then interactive:

1. Compliance rules engine runs against all declared data
2. Generates required documents per entity/principal (passport + utility bill for each UBO, certificate of incorporation for the company, etc.)
3. Bot presents the checklist and requests documents one at a time
4. For each upload: classify → extract → match against declared data → confirm or flag discrepancies
5. Tracks received vs outstanding
6. Session marked complete when all required documents received

**Processing model:** Document classification and extraction run in a background job (existing `ExtractKycDocumentJob`). The bot sends an immediate acknowledgement, then streams the result back via Turbo Streams when the job completes.

## Data Model

### New Models

#### `onboarding_sessions`

| Column | Type | Notes |
|--------|------|-------|
| id | uuid | PK |
| applicant_id | uuid | FK → merchants (Applicant STI), unique |
| current_stage | integer | enum: company_info, directors_ubos, ownership, business_activity, jurisdictions, document_collection |
| completed_stages | string[] | Array of completed stage names |
| stage_data | jsonb | Accumulated structured data per stage |
| document_checklist | jsonb | Generated from compliance rules, tracks received/outstanding |
| status | integer | enum: in_progress, completed, abandoned |
| timestamps | datetime | |

#### `onboarding_messages`

| Column | Type | Notes |
|--------|------|-------|
| id | uuid | PK |
| onboarding_session_id | uuid | FK → onboarding_sessions |
| role | integer | enum: bot, applicant |
| content | text | Message text |
| stage | string | Which stage this message belongs to |
| structured_data | jsonb | Extracted structured data from this message |
| created_at | datetime | |

### Changes to Existing Models

| Model | Change |
|-------|--------|
| `KycPrincipal` | Add `source` enum: `document_extracted` (0, default), `applicant_declared` (1) |
| `Kyc::CorporateEntity` | Add `source` enum (same) |
| `Kyc::OwnershipEdge` | Add `source` enum (same) |
| `Applicant` | `has_one :onboarding_session` |

## Service Architecture

### `Onboarding::ConversationEngine`

Orchestrator. Receives applicant message, coordinates state machine + inference adapter + data capture, returns bot response.

```ruby
Onboarding::ConversationEngine.respond(
  session:,       # OnboardingSession
  user_message:   # String
) # => { bot_message: String, extracted_data: Hash, stage_changed: Boolean }
```

### `Onboarding::StateMachine`

Deterministic stage management — required fields, validation, transitions:

```ruby
Onboarding::StateMachine.current_stage(session)     # => :directors_ubos
Onboarding::StateMachine.missing_fields(session)     # => [:date_of_birth, :nationality]
Onboarding::StateMachine.validate_field(:full_name, "Joe Bloggs")  # => { valid: true }
Onboarding::StateMachine.stage_complete?(session)    # => false
Onboarding::StateMachine.advance!(session)           # => :ownership
```

### `Onboarding::PromptBuilder`

Constructs Claude prompts per interaction. Includes system instructions, current stage context, collected data, recent message history, and structured JSON extraction instructions.

### `Onboarding::DataCaptureService`

Persists validated structured data — creates KYC model records with `source: :applicant_declared`, updates session `stage_data`, handles looping stages.

### `Onboarding::DocumentCollectionService`

Stage 6 handler — generates checklist from compliance rules, processes uploads through the existing classify → extract → match pipeline, tracks received/outstanding, returns conversational feedback.

## Chat UI

- **Stimulus controller** (`onboarding_chat_controller.js`) for the chat interface
- **Turbo Streams** over ActionCable for real-time bot responses
- Message input with file upload button (visible from Stage 6)
- Progress indicator showing current stage
- Mobile-responsive
- Admin view: read-only transcript tab on the applicant page

## Integration with Existing Pipeline

```
Chatbot                          Existing Admin Flow
   │                                    │
   ├─ Declares data ─────────► KYC Models (source: declared)
   │                                    │
   ├─ Uploads documents ─────► KycDocument ──► Classifier ──► Extractor
   │                                    │
   │                           Cross-Reference Service
   │                           (compares declared vs extracted)
   │                                    │
   │                           Compliance Rules Engine
   │                           (same rules, same assessment)
   │                                    │
   └─ Bot confirms ◄─────────── Validation Warnings
                                        │
                                  Admin Reviews
                                  (transcript + data)
```

## Non-Functional Requirements

| Requirement | Detail |
|-------------|--------|
| **Latency** | < 3s text responses, < 10s document processing |
| **Cost** | 10-20 Claude API calls per complete onboarding. Monitor prompt length. |
| **Security** | PII encrypted at rest. File uploads scanned. No PII in logs. |
| **Audit trail** | Every message and data capture timestamped. Source enum provides provenance. |
| **Rate limiting** | Max 100 messages per session to prevent abuse. |
| **Extraction readiness** | Service boundary allows extraction to standalone app. |

## Out of Scope (v1)

- OAuth / SSO for applicant auth
- Multi-language bot (documents can be multilingual, bot speaks English)
- Real-time admin intervention in chat
- Automated PEP/sanctions screening
- Payment or fee collection
- Mobile native app

## Success Criteria

1. Applicant completes full onboarding conversationally without admin help
2. Declared data appears in admin UI with source badges
3. Document checklist is accurate based on declared data
4. Uploaded documents are classified, extracted, and cross-referenced inline
5. Discrepancies surface as validation warnings
6. Applicant can resume across sessions
7. Admin can view transcript and declared data read-only
