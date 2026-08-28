# RFC: Gooo interchange envelope v1

Status: Experimental specification fixtures, no released-domain adoption

## Purpose

Define an optional evidence-bearing file protocol for independent Gooo domain
projects. This specification responds to the public gooo-link v0.4.0-dev
observation. It does not import domain source code and does not become a
required release gate for local-ledger, design-evidence, or infra-evidence.

## Canonical bundle

Each generated fixture bundle has exactly five top-level files:

- project.json;
- relations.ndjson;
- conformance.json;
- unknowns.ndjson, including when it has zero rows;
- checksums.txt.

Each bundle passes exactly six local checks: exact file set, project identity,
left and right relation anchors, UNKNOWN tuple completeness, SHA-256 checksums,
and deterministic replay. External required gates are exactly zero.

## Relation semantics

A relation state is MATCH, MISMATCH, or UNKNOWN. All relations retain stage,
step, reason, unknown_class, and next_operation. UNKNOWN requires a non-null
unknown_class and an executable next operation. It remains in the relation
denominator and is copied to unknowns.ndjson.

## Current evidence boundary

CI generates nine golden bundles: three domains multiplied by MATCH, MISMATCH,
and UNKNOWN. This establishes specification fixture conformance 9/9, generated
files 45/45, local checks 54/54, and replay 9/9.

These are synthetic specification fixtures. Released-domain adoption remains
0/3 and connector implementation remains NOT_STARTED. A later domain may
publish an advisory bundle independently; no synchronized rollout is required.
