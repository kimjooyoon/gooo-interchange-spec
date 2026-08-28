#!/usr/bin/env bash
set -euo pipefail

if test "$#" -ne 3; then
  echo "usage: conform-bundle.sh BUNDLE REPLAY_BUNDLE OUTPUT" >&2
  exit 64
fi
bundle=$1
replay=$2
output=$3
checks='[]'
append_check() {
  id=$1; stage=$2; step=$3; state=$4; reason=$5; next=$6
  checks=$(jq -c --arg id "$id" --arg stage "$stage" --arg step "$step" --arg state "$state" --arg reason "$reason" --arg next "$next" \
    '.+[{id:$id,stage:$stage,step:$step,state:$state,reason:$reason,next_operation:$next,unknown_class:null}]' <<<"$checks")
}
expected=$(printf '%s\n' checksums.txt conformance.json project.json relations.ndjson unknowns.ndjson)
actual=$(find "$bundle" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' | sort)
if test "$actual" = "$expected"; then append_check EXACT_FILE_SET BUNDLE VERIFY_EXACT_FILE_SET CLOSED EXACT_FILE_SET_OBSERVED NONE; else append_check EXACT_FILE_SET BUNDLE VERIFY_EXACT_FILE_SET REFUTED FILE_SET_MISMATCH RESTORE_EXACT_FILE_SET; fi
if jq -e '.schema=="gooo/interchange/project/v1" and (.project_id|type)=="string" and (.domain|type)=="string" and (.release.target_commit_sha|test("^[0-9a-f]{40}$")) and (.release.source_asset_sha256|test("^[0-9a-f]{64}$")) and .relation_count==1 and (.unknown_count==0 or .unknown_count==1)' "$bundle/project.json" >/dev/null 2>&1 &&
   jq -e '.schema=="gooo/interchange/conformance/v1" and .required_files==5 and (.required_local_checks|length)==6 and .external_required_gates==0' "$bundle/conformance.json" >/dev/null 2>&1; then
  append_check PROJECT_IDENTITY IDENTITY VERIFY_PROJECT_IDENTITY CLOSED PROJECT_IDENTITY_VERIFIED NONE
else append_check PROJECT_IDENTITY IDENTITY VERIFY_PROJECT_IDENTITY REFUTED PROJECT_IDENTITY_MISMATCH RESTORE_PROJECT_IDENTITY; fi
if jq -s -e 'length==1 and .[0].schema=="gooo/interchange/relation/v1" and (.[]|.state|IN("MATCH","MISMATCH","UNKNOWN")) and all(.[];(.left.kind|type)=="string" and (.left.id|type)=="string" and (.right.kind|type)=="string" and (.right.id|type)=="string")' "$bundle/relations.ndjson" >/dev/null 2>&1; then
  append_check RELATION_ANCHORS RELATION VERIFY_RELATION_ANCHORS CLOSED RELATION_ANCHORS_VERIFIED NONE
else append_check RELATION_ANCHORS RELATION VERIFY_RELATION_ANCHORS REFUTED RELATION_ANCHOR_MISMATCH RESTORE_RELATION_ANCHORS; fi
if jq -s -e --slurpfile project "$bundle/project.json" --slurpfile unknowns "$bundle/unknowns.ndjson" '
  ([.[]|select(.state=="UNKNOWN")]) as $relations_unknown |
  ($unknowns[0]//[]) as $unknown_rows |
  ($relations_unknown|length)==$project[0].unknown_count and ($unknown_rows|length)==$project[0].unknown_count and
  all($relations_unknown[];has("stage") and has("step") and has("reason") and has("unknown_class") and has("next_operation") and (.unknown_class|type)=="string" and .next_operation!="NONE") and
  ($relations_unknown==$unknown_rows)
' "$bundle/relations.ndjson" >/dev/null 2>&1; then
  append_check UNKNOWN_TUPLE UNCERTAINTY VERIFY_UNKNOWN_TUPLE CLOSED UNKNOWN_TUPLE_VERIFIED NONE
else append_check UNKNOWN_TUPLE UNCERTAINTY VERIFY_UNKNOWN_TUPLE REFUTED UNKNOWN_TUPLE_INCOMPLETE RESTORE_UNKNOWN_TUPLE; fi
if (cd "$bundle" && sha256sum -c checksums.txt >/dev/null 2>&1); then append_check SHA256_CHECKSUMS DIGEST VERIFY_SHA256_CHECKSUMS CLOSED SHA256_CHECKSUMS_VERIFIED NONE; else append_check SHA256_CHECKSUMS DIGEST VERIFY_SHA256_CHECKSUMS REFUTED SHA256_CHECKSUM_MISMATCH RESTORE_BUNDLE_FILE_CONTENT; fi
replay_equal=true
for file in checksums.txt conformance.json project.json relations.ndjson unknowns.ndjson; do cmp -s "$bundle/$file" "$replay/$file" || replay_equal=false; done
if test "$replay_equal" = true; then append_check DETERMINISTIC_REPLAY REPLAY VERIFY_DETERMINISTIC_REPLAY CLOSED DETERMINISTIC_REPLAY_VERIFIED NONE; else append_check DETERMINISTIC_REPLAY REPLAY VERIFY_DETERMINISTIC_REPLAY REFUTED NONDETERMINISTIC_BUNDLE_OUTPUT RESTORE_DETERMINISTIC_GENERATION; fi
jq -S -n --argjson checks "$checks" --slurpfile project "$bundle/project.json" '
  ([$checks[]|select(.state=="CLOSED")]|length) as $closed |
  ([$checks[]|select(.state=="REFUTED")]|length) as $refuted |
  ([$checks[]|select(.state!="CLOSED")][0]//null) as $first |
  {schema:"gooo/interchange/bundle-conformance-report/v1",fixture_id:$project[0].fixture_id,domain:$project[0].domain,
   decision:(if $refuted>0 then "FAIL_CLOSED" else "CONFORMANT" end),summary:{total:6,closed:$closed,unknown:0,refuted:$refuted,required_files:5,external_required_gates:($project[0].external_required_gates? // 0)},
   claim:(if $first==null then {state:"CLOSED",stage:null,step:null,reason:"BUNDLE_CONFORMANT",next_operation:"NONE",unknown_class:null} else {state:$first.state,stage:$first.stage,step:$first.step,reason:$first.reason,next_operation:$first.next_operation,unknown_class:$first.unknown_class} end),checks:$checks}' > "$output"
