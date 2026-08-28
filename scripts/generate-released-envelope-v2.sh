#!/usr/bin/env bash
set -euo pipefail

if test "$#" -ne 7; then
  echo "usage: generate-released-envelope-v2.sh REPOSITORY MATRIX LOCK PRODUCT_ID SOURCE REPLAY OUTPUT" >&2
  exit 64
fi
repository=$(realpath "$1")
matrix=$2
lock=$3
product_id=$4
source_file=$5
replay_file=$6
output=$(realpath -m "$7")
case "$output" in "$repository"|"$repository"/*) echo "output must be outside repository" >&2; exit 65;; esac
for file in "$matrix" "$lock" "$source_file" "$replay_file"; do test -f "$file" || exit 66; done
mkdir -p "$output"
test -z "$(find "$output" -mindepth 1 -maxdepth 1 -print -quit)"

config=$(jq -ce --arg id "$product_id" '[.products[]|select(.id==$id)]|if length==1 then .[0] else error("product cardinality") end' "$matrix")
release=$(jq -ce --arg id "$product_id" '[.products[]|select(.id==$id)]|if length==1 then .[0] else error("release cardinality") end' "$lock")
domain=$(jq -r .domain <<<"$config")
mode=$(jq -r .mode <<<"$config")
source_schema=$(jq -r .source_schema <<<"$config")
relation_array=$(jq -r .relation_array <<<"$config")
expected_relations=$(jq -r .expected_relations <<<"$config")
test "$(jq -r .schema "$source_file")" = "$source_schema"
test "$(jq --arg key "$relation_array" '.[$key]|length' "$source_file")" -eq "$expected_relations"

expected_replay_schema=$(jq -r .replay.schema <<<"$config")
test "$(jq -r .schema "$replay_file")" = "$expected_replay_schema"
satisfied_path=$(jq -c .replay.satisfied_path <<<"$config")
total_path=$(jq -c .replay.total_path <<<"$config")
source_satisfied=$(jq -r --argjson path "$satisfied_path" 'getpath($path)' "$replay_file")
source_total=$(jq -r --argjson path "$total_path" 'getpath($path)' "$replay_file")
expected_replay=$(jq -r .replay.expected <<<"$config")
test "$source_satisfied" -eq "$source_total"
test "$source_total" -eq "$expected_replay"

source_member=$(jq -r '.source_asset.member // ""' <<<"$release")
source_sha=$(jq -r .source_asset.sha256 <<<"$release")
if test -z "$source_member"; then
  test "$(sha256sum "$source_file"|awk '{print $1}')" = "$source_sha"
fi

: > "$output/evidence.ndjson"
: > "$output/relations.ndjson"
: > "$output/resolutions.ndjson"
: > "$output/unknowns.ndjson"
ordinal=0
jq -cS --arg key "$relation_array" '.[$key][]' "$source_file" | while IFS= read -r row; do
  ordinal=$((ordinal+1))
  printf -v suffix '%03d' "$ordinal"
  relation_id=$(jq -r .id <<<"$row")
  test -n "$relation_id"
  evidence_id="gooo://interchange/evidence/$product_id/$suffix"
  value_sha=$(printf '%s' "$row" | sha256sum | awk '{print $1}')
  pointer="/$relation_array/$((ordinal-1))"
  jq -cS -n --arg id "$evidence_id" --arg relation_id "$relation_id" --arg repository "$(jq -r .repository <<<"$release")" \
    --arg tag "$(jq -r .tag <<<"$release")" --arg target "$(jq -r .target_commit_sha <<<"$release")" \
    --arg asset "$(jq -r .source_asset.name <<<"$release")" --arg asset_sha "$source_sha" --arg member "$source_member" \
    --arg pointer "$pointer" --arg value_sha "$value_sha" \
    '{schema:"gooo/interchange/evidence/v2",id:$id,relation_id:$relation_id,source:{repository:$repository,tag:$tag,target_commit_sha:$target,asset_name:$asset,asset_sha256:$asset_sha,member:(if $member=="" then null else $member end),json_pointer:$pointer},observation:{kind:"RELEASED_JSON_VALUE",value_sha256:$value_sha},authority:{claim_scope:"RELEASED_DECLARATION_ONLY",semantic_truth_claimed:false}}' >> "$output/evidence.ndjson"

  if test "$mode" = DEPENDENCY; then
    jq -cS -n --argjson row "$row" --arg evidence_id "$evidence_id" \
      '{schema:"gooo/interchange/relation/v2",id:$row.id,kind:$row.kind,domain_state:"DECLARED",disposition:$row.kind,left:{kind:"ACTIVITY",id:$row.from_activity},right:{kind:"ACTIVITY",id:$row.to_activity},evidence_ids:[$evidence_id],attributes:{ordinal:$row.ordinal,label:$row.label,via_entity:$row.via_entity},authority:{domain_semantics_preserved:true,claim_resolution_embedded:false}}' >> "$output/relations.ndjson"
    jq -cS -n --arg relation_id "$relation_id" \
      '{schema:"gooo/interchange/resolution/v2",relation_id:$relation_id,state:"CLOSED",stage:null,step:null,reason:"RELEASED_TYPED_DEPENDENCY_DECLARATION_OBSERVED",unknown_class:null,next_operation:"NONE",blocked_by:[],authority:{source:"RELEASED_PRODUCT_EVIDENCE",state_inference_authorized:false}}' >> "$output/resolutions.ndjson"
  elif test "$mode" = DESIGN_DISPOSITION; then
    jq -e '.state|IN("MATCH","MISMATCH","UNKNOWN")' <<<"$row" >/dev/null
    jq -cS -n --argjson row "$row" --arg evidence_id "$evidence_id" \
      '{schema:"gooo/interchange/relation/v2",id:$row.id,kind:"DESIGN_CODE_RELATION",domain_state:$row.state,disposition:$row.disposition,left:{kind:"DESIGN_SUBJECT",id:$row.from},right:{kind:"CODE_SUBJECT",id:$row.to},evidence_ids:[$evidence_id],attributes:{review_action:$row.review_action,evidence_count:$row.evidence_count},authority:{domain_semantics_preserved:true,claim_resolution_embedded:false}}' >> "$output/relations.ndjson"
    if test "$(jq -r .state <<<"$row")" = UNKNOWN; then
      jq -e 'has("stage") and has("step") and has("reason") and has("unknown_class") and has("next_operation") and has("blocked_by") and (.blocked_by|type)=="array"' <<<"$row" >/dev/null
      jq -cS -n --argjson row "$row" \
        '{schema:"gooo/interchange/resolution/v2",relation_id:$row.id,state:"UNKNOWN",stage:$row.stage,step:$row.step,reason:$row.reason,unknown_class:$row.unknown_class,next_operation:$row.next_operation,blocked_by:$row.blocked_by,authority:{source:"RELEASED_PRODUCT_EVIDENCE",state_inference_authorized:false}}' | tee -a "$output/resolutions.ndjson" >> "$output/unknowns.ndjson"
    else
      jq -cS -n --argjson row "$row" \
        '{schema:"gooo/interchange/resolution/v2",relation_id:$row.id,state:"CLOSED",stage:null,step:null,reason:$row.reason,unknown_class:null,next_operation:"NONE",blocked_by:[],authority:{source:"RELEASED_PRODUCT_EVIDENCE",state_inference_authorized:false}}' >> "$output/resolutions.ndjson"
    fi
  else
    echo "unsupported projection mode: $mode" >&2
    exit 67
  fi
done

relation_count=$(wc -l < "$output/relations.ndjson" | tr -d ' ')
evidence_count=$(wc -l < "$output/evidence.ndjson" | tr -d ' ')
resolution_count=$(wc -l < "$output/resolutions.ndjson" | tr -d ' ')
unknown_count=$(wc -l < "$output/unknowns.ndjson" | tr -d ' ')
test "$relation_count" -eq "$expected_relations"
test "$evidence_count" -eq "$relation_count"
test "$resolution_count" -eq "$relation_count"

jq -S -n --arg project_id "$product_id" --arg domain "$domain" --arg repository "$(jq -r .repository <<<"$release")" \
  --arg tag "$(jq -r .tag <<<"$release")" --arg target "$(jq -r .target_commit_sha <<<"$release")" \
  --arg asset "$(jq -r .source_asset.name <<<"$release")" --arg asset_sha "$source_sha" --arg member "$source_member" --arg source_schema "$source_schema" \
  --argjson relation_count "$relation_count" --argjson evidence_count "$evidence_count" --argjson resolution_count "$resolution_count" --argjson unknown_count "$unknown_count" \
  '{schema:"gooo/interchange/project/v2",project_id:$project_id,domain:$domain,release:{repository:$repository,tag:$tag,target_commit_sha:$target},source:{asset_name:$asset,asset_sha256:$asset_sha,member:(if $member=="" then null else $member end),schema:$source_schema},relation_count:$relation_count,evidence_count:$evidence_count,resolution_count:$resolution_count,unknown_count:$unknown_count,authority:{projection_owner:"INTERCHANGE_SPECIFICATION",domain_release_adoption_claimed:false,source_repository_writes:0,product_generation_authorized:false}}' > "$output/project.json"

jq -S -n '{schema:"gooo/interchange/conformance/v2",required_files:8,required_local_checks:["EXACT_FILE_SET","PROJECT_IDENTITY_AND_AUTHORITY","CARDINALITIES","EVIDENCE_ANCHORS","RELATION_ANCHORS","RESOLUTION_TUPLES","UNKNOWN_SUBSET","SOURCE_REPLAY","SHA256_CHECKSUMS","DETERMINISTIC_REPLAY"],external_required_gates:0,repository_writes:0,product_generation_authorized:false}' > "$output/conformance.json"
payload_sha=$(cd "$output" && sha256sum project.json evidence.ndjson relations.ndjson resolutions.ndjson unknowns.ndjson conformance.json | sha256sum | awk '{print $1}')
jq -S -n --arg receipt_schema "$expected_replay_schema" --argjson satisfied "$source_satisfied" --argjson total "$source_total" --arg payload_sha "$payload_sha" \
  '{schema:"gooo/interchange/replay/v2",source:{receipt_schema:$receipt_schema,comparisons_satisfied:$satisfied,comparisons_total:$total,receipt_verified:true},projection:{payload_files:6,payload_sha256:$payload_sha},authority:{determinism_is_semantic_truth:false,product_execution_authorized:false}}' > "$output/replay.json"
(cd "$output" && sha256sum project.json evidence.ndjson relations.ndjson resolutions.ndjson unknowns.ndjson conformance.json replay.json > checksums.txt)
