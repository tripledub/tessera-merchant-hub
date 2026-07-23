# MH-153 Chatbot Effectiveness Review

## Purpose

Give authorised administrators evidence for assessing the onboarding chatbot's
effectiveness. The feature should reveal whether an applicant completed
onboarding, where the conversation became inefficient or stalled, and how well
chatbot-captured declarations agree with documentary evidence.

MH-153 is the parent outcome. Delivery is split into independently useful Kanban
items so the read-only review capability can ship before features that require
new persistence or matching rules.

## Delivery sequence

### 1. Read-only conversation review

Add an **Onboarding Review** tab to the existing applicant page. The tab shows:

- Session status, current stage, and progress through the six onboarding stages
- Session start and last-activity times, plus elapsed duration
- Total message count and counts by applicant and chatbot
- The complete transcript in chronological order
- Speaker, timestamp, and onboarding stage for every message
- Visual stage boundaries so reviewers can identify repetition, corrections,
  and the stage at which an applicant stopped
- Explicit states for applicants with no session, sessions with no messages,
  incomplete sessions, abandoned sessions, and completed sessions

All metrics in this item are derived from existing `OnboardingSession` and
`OnboardingMessage` records. It requires no schema migration.

### 2. Data-quality comparison

Show applicant-declared and document-extracted principals, corporate entities,
and ownership relationships with clear provenance.

A value is labelled a **conflict** only after its declared and extracted records
have been matched with sufficient confidence. Records that cannot be matched
are shown as **unmatched**, and records without documentary support are shown as
**unverified**. The interface must not present fuzzy name similarity alone as a
confirmed contradiction.

Matching and field comparison belong in dedicated domain objects with focused
tests, not in templates or presenters. The exact matching rules will be designed
from the identifiers and attributes available when this item begins.

### 3. Persistent reviewer assessment

Allow an authorised administrator to save an assessment of a session:

- Overall outcome
- One or more categories such as successful, incorrect, confusing, repetitive,
  or missing information
- Optional reviewer notes
- Reviewer identity and timestamps

Assessment records are appendable audit evidence. Editing and retention
behaviour will be specified with this item before its migration is introduced.

### 4. Chatbot version traceability

Capture the chatbot, model, and prompt version used by future onboarding
sessions, then display those values in the review tab. Historical sessions with
no version metadata show an explicit unavailable state; the application does
not infer versions retrospectively.

## First delivery architecture

The first Kanban item follows the application's existing applicant-tab pattern:

- Add `onboarding_review` to the applicant controller's tab allowlist.
- Add a lazy-loaded tab and partial to the applicant show page.
- Introduce a dedicated onboarding-review presenter responsible for progress,
  counts, duration, status labels, and transcript grouping.
- Eager-load messages in chronological order when serving the tab.
- Keep templates limited to accessible display markup and existing Tailwind
  component styles.
- Reuse existing authorisation on the applicant show/tab action. The review is
  read-only and introduces no new mutation endpoint.

The presenter accepts an applicant and handles the absence of an onboarding
session. It exposes display-ready session metrics and ordered stage groups. A
stage group contains a stage name and ordered messages; empty completed stages
may be represented in the progress summary but do not create empty transcript
sections.

## Data flow

1. An authorised administrator selects **Onboarding Review**.
2. The existing tabs controller requests the applicant tab endpoint.
3. The controller authorises access and loads the applicant's onboarding
   session with its messages.
4. The presenter derives session metrics and groups messages by their persisted
   stage while preserving chronological order within each group.
5. The partial renders the summary, progress, transcript, or the appropriate
   empty state.

Duration is the interval from session creation to completion/abandonment time
when a dedicated terminal timestamp eventually exists. For the first delivery,
the best available end is `updated_at`; the UI labels this as last activity
rather than claiming it is a precise completion time.

## Error and edge-case handling

- No onboarding session: explain that onboarding has not started.
- Session with no messages: show session metadata and an empty-transcript state.
- Unknown or missing message stage: group under **Unknown stage** without losing
  the message.
- Active session: label duration as elapsed through last activity.
- Abandoned or incomplete session: retain all available messages and clearly
  show the terminal/current state.
- Long content: wrap within the transcript; do not truncate the evidence.
- Markdown in bot messages: use the same safe rendering behaviour as the
  applicant-facing conversation, without allowing executable HTML.

## Testing

The first delivery includes:

- Presenter specs for no session, status/progress, counts, duration, ordering,
  grouping, missing stages, and display labels
- Request specs for authorisation, the allowed tab, session metrics, transcript
  content, and empty states
- View-level coverage where needed for safe markdown rendering and accessible
  transcript structure
- Regression coverage ensuring unknown tab names still return `404`

Later items add isolated unit tests for matching/comparison rules and request or
model tests for assessment persistence and version metadata.

## Out of scope for the first delivery

- Saving reviewer ratings or notes
- Automated discrepancy matching
- Retrospective chatbot/model/prompt version inference
- Exporting sessions as a training dataset
- Automatically retraining or fine-tuning a model
- Editing applicant declarations or intervening in an active conversation

## Success criteria

The first item is successful when an authorised administrator can open an
applicant, understand the onboarding outcome and efficiency at a glance, and
inspect the full stage-labelled conversation without changing any onboarding
data. Subsequent items make data quality, reviewer judgement, and chatbot
versioning measurable without blocking that initial capability.
