# B2 — Field-level encryption + health-data consent

_Phase B (data-protection foundation), run 2 of 2. Moved forward from the original SOC
brief's Part C ([E2](E2-soc-visibility.md)) so every Phase C run encrypts its own new
fields as it adds them (roadmap standing rule 2) instead of one large retrofit migration.
Consumed by requirements-elicitation + planning at run start. Local, with KMS via
LocalStack; cost $0._

## Goal
Health data is encrypted at the field level before any feature run adds more of it, and
the app obtains explicit consent before processing it.

## Why this data is health-grade
Weight-over-time and diet logs are health data under:
- GDPR Art. 9 (in context)
- Washington My Health My Data Act
- CPRA sensitive personal information
- FTC Health Breach Notification Rule
- Apple's Health & Fitness label

They are not HIPAA (consumer app). The app stores no height and computes no BMI; if
either is ever added it inherits this classification. Greenfield's
pseudonymization + SSE posture was proportionate before this run; this run escalates.

## Scope
- **Field-level KMS envelope encryption** through the `src/orbit/crypto/` facade:
  - Covers weight values and food-entry values (name, kcal, macros).
  - A migration converts the columns.
  - Value CHECK constraints move fully to Pydantic, because DB CHECKs on ciphertext have
    to drop. Document this.
  - Totals are computed app-side (≤ 200 rows/day, already the shape).
- **KMS locally**: the key is created by Terraform in envs/local on LocalStack and
  authored for staging/prod (A2 rule). The app gets the key ID via config and reaches
  LocalStack through `AWS_ENDPOINT_URL`, with no code branch.
- **IAM**: the app role gets `kms:GenerateDataKey` + `kms:Decrypt` on that key only.
  Written now; enforced for real in E1.
- **Data classification table**, per data-protection-conventions, for every stored field.
  From here on every Phase C run adds rows for its new fields (standing rule 2). Any
  field classified health-grade that B1's covered-read list doesn't include yet is added
  to it in this run.
- **Storage this run may add**: consent records (timestamp, policy version, per user),
  and per-user data keys if that option is chosen. If either lands as a new
  `owner_uid` table, **B2 becomes the first run to add an owner-scoped table**. It then
  owns building the owner_uid-table registry and its export ∪ erase parity test, and
  adds the table to the `erase.py` cascade + AC5 (roadmap standing rule 1). Consent held
  as columns on `profiles` carries no such obligation.
- **Consent UX**: explicit consent at registration for health-data processing; data
  writes are blocked until it's accepted; revocation behavior is defined. Consent changes
  emit B1 audit events.
- **Privacy-policy text drafted** locally. The legal/counsel review is a go-live item
  (E3).

## Key decisions
- Per-user data keys (enables crypto-erasure on account deletion) vs one app-wide key
- Data-key caching policy (perf vs key-exposure window)
- Revocation semantics: stop writes only, or also erase stored data?

## Security / compliance notes
- The crypto facade stays the only crypto code path.
- No plaintext health values in logs, audit events or errors.
- Ciphertext produced under LocalStack KMS is local-only and disposable (A1).
- Standard adversarial shapes on any new consent endpoint.

## Acceptance sketch
- Encrypted at rest proven: a raw column read ≠ plaintext, and the API round-trip is
  intact.
- Consent flow blocks data writes until accepted (API + XCUITest).
- Consent events are audited via B1.
- Classification table committed.
- p95 re-measured with decrypt on the read path, still < 300 ms at ~10 concurrent.
- Checkov clean on the KMS Terraform.

## Size
Medium; crypto facade + repositories + one migration + consent UI + tests.
