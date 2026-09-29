# Testing on UAT with synthetic data

A guide for anyone testing MerchantHub on UAT (`https://uat.kynetic.id`). It explains the fake company registry, the fake people ("personas") and the generated documents you can use instead of real KYC data, and which company numbers trigger which behaviour.

Everything here is invented. **Never type a real person's or company's details into any of these pages.**

For how test cases are recorded, see [Testing with Qase](qase.md). The Qase project code is `KYN`.

## Before you start

- Sign in as a PSP admin (the seeded `psp-admin@tessera.test` account). The synthetic pages are `psp_admin` only; a PSP support user gets a 403.
- The pages have no menu link. Go to them directly by URL (below). If you get a 404, the `SYNTHETIC_DATA_ENABLED` flag is off in that environment. It is on in UAT and dev, and must never be set in production.
- **UAT is wiped on every deploy.** Applicants, documents and personas you create are gone after the next deploy. Only the committed personas listed below come back automatically. Record results in Qase as you go.

## The fake registry (Utopia)

When you create a new applicant, choose the registry jurisdiction **Utopia (test data)**, enter one of the company numbers below and press **Look up company** to preview it, or **Confirm & Create** to create the applicant. No real Companies House company is needed.

### Company scenarios

| Number | What it is | What you should see |
| --- | --- | --- |
| `XU000001` | Simple company | Two active directors become principals. No PSCs. |
| `XU000002` | Officers matching the specimen passports | Directors Alex Testperson and Morgan Lee Exampleson, each with a month/year date of birth. |
| `XU000003` | Corporate PSC chain | One director and one corporate PSC (`XU000010`). On the applicant's **Ownership** tab press **Trace ownership chain**: it follows through to an individual owner and raises an indirect UBO warning at 56.25%. |
| `XU000004` | Nominee | A corporate PSC registered in Cyprus (CY). The **Compliance** tab shows a "Nominee detected" warning naming the company and CY, plus a UBO warning. |
| `XU000005` | Resigned director | Two officers on file, but only the active one (Morgan Active) becomes a principal. |
| `XU000006` | Ownership overshoots 100% | Two PSCs whose minimum stakes already add up to at least 125%. The **Compliance** tab shows a percentage deviation warning. |

`XU000010` is only the intermediate company in the `XU000003` chain; you don't normally enter it yourself.

### Registry failure scenarios

These check the error handling without needing the real registry to fail. Enter the number, press **Look up company**, and the message should match:

| Number | Failure | Message shown |
| --- | --- | --- |
| `XU000404` | Not found | No company found with that number. |
| `XU000401` | Unauthorised | Companies House rejected our API key. |
| `XU000429` | Rate limited | Companies House rate limit reached — try again shortly. |
| `XU000503` | Unavailable | Companies House is unavailable right now — try again shortly. |

No applicant is created, and these do not alert Honeybadger. Any number not in the tables above also returns "not found".

## Personas and generated documents

A persona is a fake person you can generate documents for. Open **`/admin/synthetic/personas`**.

- **Create one** with **New persona**: given names, surname, date of birth, sex and jurisdiction. The defaults are obviously fake.
- **Generate a passport** from a persona's page: choose the place of birth, a passport number (up to 9 letters/digits, which also goes into the machine-readable zone) and an expiry (valid 2 years out, expires in 60 days, expires in 30 days, or expired yesterday). The PDF downloads. It is marked "REPUBLIC OF UTOPIA — SPECIMEN — TEST DATA", has a SPECIMEN watermark and a silhouette instead of a photo, and its MRZ has valid check digits.
- The same persona and options give the same content each time, so you can name exact inputs in a Qase case.
- The **Generated documents** table on the persona page shows who generated what and when.

Upload the downloaded PDF to an applicant like any real document. A passport for Alex Testperson uploaded to an applicant created on `XU000002` should auto-link to Alex's principal and fill in the full date of birth.

### Keeping a persona across deploys

Personas are wiped with the rest of the database on each deploy, except those committed to the repo under `config/synthetic/personas/`. The **Export to YAML** button writes the file **on the UAT server only**, and that copy is also gone after the next deploy. To keep a persona permanently:

1. Create and export it on a local dev instance (`SYNTHETIC_DATA_ENABLED=true bin/rails server`).
2. Commit the new `config/synthetic/personas/<slug>.yml` in a pull request.

After each UAT deploy the committed files are reloaded automatically (`rails kyc:synthetic:seed`). Two personas ship today: `alex-testperson` and `morgan-lee-exampleson`.

## Scenarios

**`/admin/synthetic/scenarios`** lists named scenarios. Each one ties together a registry company number, the personas playing its officers, the documents to generate for them, the expected outcome ("ground truth") and its Qase case.

- **Download document pack** gives you a zip of every document the scenario needs, ready to upload.
- Today there is one: **Two directors, one uploaded passport** (`XU000002`, Qase [KYN-29](https://app.qase.io/case/KYN-29)).

Run a scenario end to end: create an applicant on its company number, upload the documents from the pack, then compare what the app shows with the ground truth on the page.

## Qase cases

| Case | Covers |
| --- | --- |
| KYN-29 | Two directors, one uploaded passport (`XU000002`) |
| KYN-30 / 31 / 32 / 33 | Registry failures: not found / unauthorised / rate limited / unavailable |
| KYN-34 | Corporate PSC chain (`XU000003`) |
| KYN-35 | Nominee corporate PSC (`XU000004`) |
| KYN-36 | Resigned director (`XU000005`) |
| KYN-37 | Ownership overshoots 100% (`XU000006`) |

## If something looks wrong

- **404 on a synthetic page**: the flag is off in that environment, or you are not signed in.
- **Persona missing after a deploy**: it was never committed to `config/synthetic/personas/` (see above).
- **A scenario disagrees with its ground truth**: that is a finding. Note the applicant, the company number and what you saw in the Qase result.
- Adding new scenarios or personas is a repo change: see `config/synthetic/registry_scenarios.yml`, `config/synthetic/personas/` and `config/synthetic/scenarios/`.
