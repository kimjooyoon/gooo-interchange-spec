# Released-domain evidence envelope v2

## Decision

The v2 experiment projects three immutable product releases into one canonical, read-only envelope without claiming that any product has adopted the format.

The motivating released observation is exact: three domains and nine verified assets exist, while machine-readable replay is 2/3 and canonical envelope adoption is 0/3. A connector that understands each product JSON directly would centralize product semantics. This protocol instead separates domain relation, evidence anchor, and claim resolution.

## Semantic boundary

A domain state such as MATCH, MISMATCH, REQUIRES, or EMITS is not a claim resolution. Every relation keeps the product state unchanged. A separate resolution row uses only CLOSED, UNKNOWN, or REFUTED.

UNKNOWN requires six coordinates: stage, step, reason, unknown_class, next_operation, and blocked_by. Direct missing evidence uses an empty blocked_by array. Dependency-blocked evidence records the minimal stable frontier. Known contradictions use REFUTED and never degrade to UNKNOWN.

## Exact denominator

- meta cells: 12
- proof classes: FOUNDATION 4, COHERENCE 4, REGRESSION 4
- indicator classes: DRIVER 4, OUTCOME 4, GUARDRAIL 4
- released products observed: 3
- product relations: Local 8, Design 4, Infra 8, total 20
- evidence anchors: 20
- resolution rows: 20
- source replay receipts: 3/3
- source replay comparisons: 19/19
- envelope files: 8 per product, 24 total
- local checks: 10 per product, 30 total
- valid UNKNOWN cases: 1 with 6/6 coordinates
- fail-closed counterexamples: 5
- cross-project required gates: 0
- repository writes: 0
- local tests: 0

The eight files are project.json, evidence.ndjson, relations.ndjson, resolutions.ndjson, unknowns.ndjson, replay.json, conformance.json, and checksums.txt.

## Authority

The specification may read immutable public release assets, verify hashes and schemas, and write projections outside product repositories. It may not modify products, generate product code, run product tests, infer semantic truth, merge changes, or create a required cross-project status check.

These envelopes are specification-owned projections. Released product adoption remains 0/3 until each product independently publishes the format from its own CI. The next operation after this experiment is optional product-owned adoption, not connector promotion.

## Munchausen choices

FOUNDATION binds the current Core, Local, Design, and Infra releases. COHERENCE separates relations, evidence, resolutions, and the exact envelope. REGRESSION preserves UNKNOWN coordinates, deterministic replay, counterexample rejection, and read-only authority.

## Non-claims

- Conformance does not prove external utility.
- Deterministic replay does not prove a relation true.
- A reviewed design mismatch is not automatically REFUTED.
- A declared dependency is observed, not asserted as runtime causality.
- Specification-owned projection is not domain release adoption.
- This RFC does not authorize Semantic Forge, common generation, or central orchestration.
