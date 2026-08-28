# Released-domain consumer kit v2

Status: experimental

## Decision

Publish a generator-free, read-only consumer kit from the immutable v0.2.0-dev
released-domain envelope specification. The kit lets a product validate its own
eight-file envelope without checking out this repository or copying validator
source into the product.

This is specification packaging, not product adoption. Released-domain adoption
remains 0/3 until Local Ledger, Design Evidence, and Infra Evidence each publish
their own digest-pinned envelope and replay receipt.

## Fixed denominator

The completeness denominator is exactly 12 cells and exactly 12 Gooo activities.
FOUNDATION, COHERENCE, and REGRESSION own four cells each. DRIVER, OUTCOME, and
GUARDRAIL own four cells each. Counts are reported separately and are never
combined into a score.

## Exact kit

Each archive contains exactly 11 regular files:

1. Six v2 JSON schemas.
2. One read-only envelope conformer.
3. One released-domain envelope denominator.
4. One released-domain envelope RFC.
5. One manifest.
6. One checksum file with exactly 10 entries.

The kit contains zero generators. It accepts two caller-owned envelope
directories and writes one report to a caller-owned output path. It does not
modify a product repository, invoke product tests, infer domain truth, publish
artifacts, or close product adoption.

## Released evidence

CI downloads three assets from v0.2.0-dev by release asset ID and SHA-256:
the specification report, aggregate, and CI artifact. The included conformer is
then run against the three released envelope projections. This observation
expects 3 envelopes and 30/30 local checks.

Passing the same immutable envelope as both inputs only rechecks the kit's
read-only interface. The v0.2.0-dev specification report remains the authority
for the original source-to-projection replay comparison.

## Uncertainty and refutation

An unavailable specification release is UNKNOWN. The direct record is emitted
at SPEC_RELEASE with stage, step, reason, unknown_class, next_operation, and an
empty blocked_by list. Every dependent cell reports DEPENDENCY_BLOCKED with a
minimal stable cell frontier.

A known contradiction is REFUTED. An included generator, authority escalation,
invalid checksum, invalid envelope, or unrecognized Core decision cannot become
UNKNOWN or CLOSED. Only explicit Core CLOSED, UNKNOWN, and REFUTED receipts are
accepted; values such as FIXED_POINT fail closed.

## Authority

Repository writes, local test executions, product generation, product adoption
claims, and cross-project required gates are all fixed at zero. Products consume
the future kit release by immutable tag and digest. Their CI remains optional and
independent; this repository does not become a required gate.

## Utility and improvement

Conformance is not utility. External utility evidence is currently 0/1 and
therefore UNKNOWN. Exact before/after pairs are currently 0/1 and improvement is
also UNKNOWN. Neither claim may be closed by this repository's own CI.
