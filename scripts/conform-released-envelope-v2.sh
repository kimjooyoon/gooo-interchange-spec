#!/usr/bin/env bash
set -euo pipefail

if test "$#" -ne 3; then
  echo "usage: conform-released-envelope-v2.sh BUNDLE REPLAY_BUNDLE OUTPUT" >&2
  exit 64
fi
bundle=$1
replay_bundle=$2
output=$3
checks='[]'
append_check() {
  id=$1; state=$2; reason=$3; next=$4
  checks=$(jq -c --arg id "$id" --arg state "$state" --arg reason "$reason" --arg next "$next" '.+[{id:$id,state:$state,stage:$id,step:("VERIFY_"+$id),reason:$reason,unknown_class:null,next_operation:$next}]' <<<"$checks")
}
closed() { append_check "$1" CLOSED "$2" NONE; }
refuted() { append_check "$1" REFUTED "$2" "$3"; }

expected=$(printf '%s\n' checksums.txt conformance.json evidence.ndjson project.json relations.ndjson replay.json resolutions.ndjson unknowns.ndjson)
actual=$(find "$bundle" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' | sort)
if test "$actual" = "$expected"; then closed EXACT_FILE_SET EXACT_FILE_SET_OBSERVED; else refuted EXACT_FILE_SET FILE_SET_MISMATCH RESTORE_EXACT_FILE_SET; fi

if jq -e '.schema=="gooo/interchange/project/v2" and (.project_id|type)=="string" and (.release.target_commit_sha|test("^[0-9a-f]{40}$")) and (.source.asset_sha256|test("^[0-9a-f]{64}$")) and .authority=={projection_owner:"INTERCHANGE_SPECIFICATION",domain_release_adoption_claimed:false,source_repository_writes:0,product_generation_authorized:false}' "$bundle/project.json" >/dev/null 2>&1 &&
   jq -e '.schema=="gooo/interchange/conformance/v2" and .required_files==8 and (.required_local_checks|length)==10 and .external_required_gates==0 and .repository_writes==0 and .product_generation_authorized==false' "$bundle/conformance.json" >/dev/null 2>&1; then
  closed PROJECT_IDENTITY_AND_AUTHORITY PROJECT_IDENTITY_AND_AUTHORITY_VERIFIED
else refuted PROJECT_IDENTITY_AND_AUTHORITY PROJECT_IDENTITY_OR_AUTHORITY_MISMATCH RESTORE_PROJECT_IDENTITY_AND_READ_ONLY_AUTHORITY; fi

relations=$(wc -l < "$bundle/relations.ndjson" | tr -d ' ')
evidence=$(wc -l < "$bundle/evidence.ndjson" | tr -d ' ')
resolutions=$(wc -l < "$bundle/resolutions.ndjson" | tr -d ' ')
unknowns=$(wc -l < "$bundle/unknowns.ndjson" | tr -d ' ')
if jq -e --argjson relations "$relations" --argjson evidence "$evidence" --argjson resolutions "$resolutions" --argjson unknowns "$unknowns" '.relation_count==$relations and .evidence_count==$evidence and .resolution_count==$resolutions and .unknown_count==$unknowns and $relations>0 and $relations==$evidence and $relations==$resolutions' "$bundle/project.json" >/dev/null; then
  closed CARDINALITIES CARDINALITIES_VERIFIED
else refuted CARDINALITIES CARDINALITY_MISMATCH RESTORE_DECLARED_CARDINALITIES; fi

if jq -n -e --slurpfile project "$bundle/project.json" --slurpfile evidence "$bundle/evidence.ndjson" '
  ($project[0]) as $p | ($evidence|length)==$p.evidence_count and ([$evidence[].id]|unique|length)==($evidence|length) and
  all($evidence[];.schema=="gooo/interchange/evidence/v2" and (.id|type)=="string" and (.relation_id|type)=="string" and .source.repository==$p.release.repository and .source.tag==$p.release.tag and .source.target_commit_sha==$p.release.target_commit_sha and .source.asset_sha256==$p.source.asset_sha256 and (.source.json_pointer|startswith("/")) and (.observation.value_sha256|test("^[0-9a-f]{64}$")) and .authority=={claim_scope:"RELEASED_DECLARATION_ONLY",semantic_truth_claimed:false})' >/dev/null; then
  closed EVIDENCE_ANCHORS EVIDENCE_ANCHORS_VERIFIED
else refuted EVIDENCE_ANCHORS EVIDENCE_ANCHOR_MISMATCH RESTORE_EVIDENCE_ANCHORS; fi

if jq -n -e --slurpfile relations "$bundle/relations.ndjson" --slurpfile evidence "$bundle/evidence.ndjson" '
  ($evidence|INDEX(.id)) as $index | ([$relations[].id]|unique|length)==($relations|length) and
  all($relations[];.schema=="gooo/interchange/relation/v2" and (.kind|type)=="string" and (.domain_state|type)=="string" and (.disposition|type)=="string" and (.left.id|type)=="string" and (.right.id|type)=="string" and (.evidence_ids|length)==1 and $index[.evidence_ids[0]]!=null and .authority=={domain_semantics_preserved:true,claim_resolution_embedded:false})' >/dev/null; then
  closed RELATION_ANCHORS RELATION_ANCHORS_VERIFIED
else refuted RELATION_ANCHORS RELATION_ANCHOR_MISMATCH RESTORE_RELATION_ANCHORS; fi

if jq -n -e --slurpfile relations "$bundle/relations.ndjson" --slurpfile resolutions "$bundle/resolutions.ndjson" '
  ($relations|INDEX(.id)) as $index | ([$resolutions[].relation_id]|unique|length)==($resolutions|length) and
  all($resolutions[];
    .schema=="gooo/interchange/resolution/v2" and $index[.relation_id]!=null and has("stage") and has("step") and has("reason") and has("unknown_class") and has("next_operation") and has("blocked_by") and (.blocked_by|type)=="array" and
    (if .state=="CLOSED" then .stage==null and .step==null and .unknown_class==null and .next_operation=="NONE" and (.blocked_by|length)==0
     elif .state=="UNKNOWN" then (.stage|type)=="string" and (.step|type)=="string" and (.unknown_class|type)=="string" and .next_operation!="NONE"
     elif .state=="REFUTED" then (.stage|type)=="string" and (.step|type)=="string" and .unknown_class==null and .next_operation!="NONE"
     else false end) and .authority=={source:"RELEASED_PRODUCT_EVIDENCE",state_inference_authorized:false})' >/dev/null; then
  closed RESOLUTION_TUPLES RESOLUTION_TUPLES_VERIFIED
else refuted RESOLUTION_TUPLES RESOLUTION_TUPLE_INVALID RESTORE_COMPLETE_RESOLUTION_TUPLES; fi

if jq -n -e --slurpfile resolutions "$bundle/resolutions.ndjson" --slurpfile unknowns "$bundle/unknowns.ndjson" '([$resolutions[]|select(.state=="UNKNOWN")]|sort_by(.relation_id))==($unknowns|sort_by(.relation_id))' >/dev/null; then
  closed UNKNOWN_SUBSET UNKNOWN_SUBSET_VERIFIED
else refuted UNKNOWN_SUBSET UNKNOWN_SUBSET_MISMATCH RESTORE_UNKNOWN_SUBSET; fi

payload_sha=$(cd "$bundle" && sha256sum project.json evidence.ndjson relations.ndjson resolutions.ndjson unknowns.ndjson conformance.json | sha256sum | awk '{print $1}')
if jq -e --arg payload_sha "$payload_sha" '.schema=="gooo/interchange/replay/v2" and .source.receipt_verified==true and .source.comparisons_satisfied==.source.comparisons_total and .source.comparisons_total>0 and .projection.payload_files==6 and .projection.payload_sha256==$payload_sha and .authority=={determinism_is_semantic_truth:false,product_execution_authorized:false}' "$bundle/replay.json" >/dev/null; then
  closed SOURCE_REPLAY SOURCE_REPLAY_VERIFIED
else refuted SOURCE_REPLAY SOURCE_REPLAY_MISMATCH RESTORE_SOURCE_REPLAY_RECEIPT; fi

if (cd "$bundle" && sha256sum -c checksums.txt >/dev/null 2>&1); then closed SHA256_CHECKSUMS SHA256_CHECKSUMS_VERIFIED; else refuted SHA256_CHECKSUMS SHA256_CHECKSUM_MISMATCH RESTORE_BUNDLE_CONTENT; fi

replay_equal=true
for file in checksums.txt conformance.json evidence.ndjson project.json relations.ndjson replay.json resolutions.ndjson unknowns.ndjson; do cmp -s "$bundle/$file" "$replay_bundle/$file" || replay_equal=false; done
if test "$replay_equal" = true; then closed DETERMINISTIC_REPLAY DETERMINISTIC_REPLAY_VERIFIED; else refuted DETERMINISTIC_REPLAY NONDETERMINISTIC_ENVELOPE RESTORE_DETERMINISTIC_PROJECTION; fi

jq -S -n --argjson checks "$checks" --slurpfile project "$bundle/project.json" '
  ([$checks[]|select(.state=="CLOSED")]|length) as $closed | ([$checks[]|select(.state=="REFUTED")]|length) as $refuted |
  ([$checks[]|select(.state!="CLOSED")][0]//null) as $first |
  {schema:"gooo/interchange/envelope-conformance-report/v2",project_id:$project[0].project_id,domain:$project[0].domain,decision:(if $refuted>0 then "FAIL_CLOSED" else "CONFORMANT" end),summary:{total:10,closed:$closed,unknown:0,refuted:$refuted,files:8,relations:$project[0].relation_count,evidence:$project[0].evidence_count,resolutions:$project[0].resolution_count,unknowns:$project[0].unknown_count,external_required_gates:0},claim:(if $first==null then {state:"CLOSED",stage:null,step:null,reason:"RELEASED_DOMAIN_ENVELOPE_CONFORMANT",unknown_class:null,next_operation:"NONE",blocked_by:[]} else {state:"REFUTED",stage:$first.stage,step:$first.step,reason:$first.reason,unknown_class:null,next_operation:$first.next_operation,blocked_by:[$first.id]} end),checks:$checks}' > "$output"
