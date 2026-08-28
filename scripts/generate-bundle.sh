#!/usr/bin/env bash
set -euo pipefail

if test "$#" -ne 4; then
  echo "usage: generate-bundle.sh REPOSITORY MATRIX FIXTURE_ID OUTPUT" >&2
  exit 64
fi

repository=$(realpath "$1")
matrix=$2
fixture_id=$3
output=$(realpath -m "$4")
case "$output" in "$repository"|"$repository"/*) echo "output must be outside repository" >&2; exit 65;; esac
test -f "$matrix"
fixture=$(jq -c --arg id "$fixture_id" '[.fixtures[]|select(.id==$id)]|if length==1 then .[0] else error("fixture cardinality") end' "$matrix")
jq -e '
  .domain as $domain | .project as $project | .relation as $relation |
  ($domain|IN("local-ledger","design-evidence","infra-evidence")) and
  ($project.id|type)=="string" and ($project.repository|type)=="string" and ($project.tag|type)=="string" and
  ($project.target_commit_sha|test("^[0-9a-f]{40}$")) and ($project.source_asset_sha256|test("^[0-9a-f]{64}$")) and
  ($relation.state|IN("MATCH","MISMATCH","UNKNOWN")) and
  ($relation.left.kind|type)=="string" and ($relation.left.id|type)=="string" and
  ($relation.right.kind|type)=="string" and ($relation.right.id|type)=="string" and
  ($relation.expected_sha256|test("^[0-9a-f]{64}$")) and
  (($relation.state=="UNKNOWN" and $relation.observed_sha256==null and ($relation.unknown_class|type)=="string" and ($relation.next_operation|type)=="string" and $relation.next_operation!="NONE") or
   ($relation.state!="UNKNOWN" and ($relation.observed_sha256|test("^[0-9a-f]{64}$")) and $relation.unknown_class==null)) and
  ($relation.stage|type)=="string" and ($relation.step|type)=="string" and ($relation.reason|type)=="string" and ($relation.next_operation|type)=="string"
' <<<"$fixture" >/dev/null
mkdir -p "$output"
test -z "$(find "$output" -mindepth 1 -maxdepth 1 -print -quit)"
unknown_count=$(jq -r 'if .relation.state=="UNKNOWN" then 1 else 0 end' <<<"$fixture")
jq -S -n --argjson fixture "$fixture" --argjson unknown_count "$unknown_count" '
  {schema:"gooo/interchange/project/v1",project_id:$fixture.project.id,domain:$fixture.domain,fixture_id:$fixture.id,
   release:{repository:$fixture.project.repository,tag:$fixture.project.tag,target_commit_sha:$fixture.project.target_commit_sha,source_asset_sha256:$fixture.project.source_asset_sha256},
   relation_count:1,unknown_count:$unknown_count}' > "$output/project.json"
jq -S -c -n --argjson fixture "$fixture" '
  {schema:"gooo/interchange/relation/v1",id:("gooo://interchange/relation/"+$fixture.id),kind:$fixture.relation.kind,state:$fixture.relation.state,
   left:$fixture.relation.left,right:$fixture.relation.right,evidence:{expected_sha256:$fixture.relation.expected_sha256,observed_sha256:$fixture.relation.observed_sha256},
   stage:$fixture.relation.stage,step:$fixture.relation.step,reason:$fixture.relation.reason,unknown_class:$fixture.relation.unknown_class,next_operation:$fixture.relation.next_operation}' > "$output/relations.ndjson"
if test "$unknown_count" -eq 1; then cp "$output/relations.ndjson" "$output/unknowns.ndjson"; else : > "$output/unknowns.ndjson"; fi
jq -S -n --arg fixture_id "$fixture_id" '
  {schema:"gooo/interchange/conformance/v1",fixture_id:$fixture_id,required_files:5,
   required_local_checks:["EXACT_FILE_SET","PROJECT_IDENTITY","RELATION_ANCHORS","UNKNOWN_TUPLE","SHA256_CHECKSUMS","DETERMINISTIC_REPLAY"],external_required_gates:0}' > "$output/conformance.json"
(cd "$output" && sha256sum project.json relations.ndjson unknowns.ndjson conformance.json > checksums.txt)
