#!/usr/bin/env bash
set -euo pipefail

if test "$#" -ne 11; then
  echo "usage: evaluate-interchange.sh GRAPH CORE_RESOLUTIONS DENOMINATOR CORE_LOCK LINK_LOCK LINK_RELEASE LINK_OBSERVATION AGGREGATE RUNTIME OUTPUT SCENARIO" >&2
  exit 64
fi
graph=$1; core=$2; denominator=$3; core_lock=$4; link_lock=$5; link_release=$6; link_observation=$7; aggregate=$8; runtime=$9; output=${10}; scenario=${11}
for file in "$graph" "$core" "$denominator" "$core_lock" "$link_lock" "$link_release" "$link_observation" "$aggregate" "$runtime"; do test -f "$file" || exit 66; done
jq -S -n --slurpfile graph "$graph" --slurpfile core "$core" --slurpfile denominator "$denominator" --slurpfile core_lock "$core_lock" \
  --slurpfile link_lock "$link_lock" --slurpfile link_release "$link_release" --slurpfile link "$link_observation" --slurpfile aggregate "$aggregate" --slurpfile runtime "$runtime" --arg scenario "$scenario" '
  ($denominator[0]) as $d |
  def expected_core: {repository:$core_lock[0].repository,tag:$core_lock[0].tag,tag_object_sha:$core_lock[0].tag_object_sha,target_commit_sha:$core_lock[0].target_commit_sha,binary_asset:$core_lock[0].asset.name,binary_sha256:$core_lock[0].asset.sha256,resolution_schema:$core_lock[0].resolution_schema};
  def closed_fact: {state:"CLOSED",reason:"FACT_OBSERVED",next_operation:"NONE",unknown_class:null,resolution:"EXACT",blocked_by:[]};
  def unknown_fact($reason;$next): {state:"UNKNOWN",reason:$reason,next_operation:$next,unknown_class:"DIRECT_MISSING",resolution:"PREREQUISITE_CLASS",blocked_by:[]};
  def refuted_fact($reason;$next): {state:"REFUTED",reason:$reason,next_operation:$next,unknown_class:null,resolution:"EXACT",blocked_by:[]};
  def resolution($cell):
    if $core[0].core_release!=expected_core then refuted_fact("CORE_RELEASE_IDENTITY_MISMATCH";"RESTORE_PINNED_CORE_RELEASE")+{stage:"CORE_RELEASE",step:"BIND_CORE_RELEASE_IDENTITY"}
    else ([$core[0].receipts[]?|select(.selector.name?==$cell.activity)]) as $r |
      if ($r|length)==0 then unknown_fact("CORE_ACTIVITY_RESOLUTION_RECEIPT_UNAVAILABLE";"PROVIDE_CORE_ACTIVITY_RESOLUTION_RECEIPT")+{stage:"RESOLUTION_OBSERVATION",step:"BIND_CORE_ACTIVITY_RESOLUTION_RECEIPT"}
      elif ($r|length)>1 then refuted_fact("DUPLICATE_CORE_ACTIVITY_RESOLUTION_RECEIPT";"REMOVE_DUPLICATE_CORE_ACTIVITY_RESOLUTION_RECEIPT")+{stage:"RESOLUTION_OBSERVATION",step:"BIND_CORE_ACTIVITY_RESOLUTION_RECEIPT"}
      else ($r[0]) as $receipt |
        if $receipt.schema!="gooo/activity-cardinality-resolution/v1" or $receipt.selector.name!=$cell.activity or $receipt.subject.source_file!="examples/interchange/main.gooo" then refuted_fact("INVALID_CORE_ACTIVITY_RESOLUTION_RECEIPT";"RESTORE_CORE_ACTIVITY_RESOLUTION_RECEIPT")+{stage:"RESOLUTION_OBSERVATION",step:"VALIDATE_CORE_ACTIVITY_RESOLUTION_RECEIPT"}
        elif $receipt.decision=="CLOSED" and $receipt.claim.state=="CLOSED" and $receipt.occurrences==1 and $receipt.claim.reason=="ACTIVITY_UNIQUELY_RESOLVED" then closed_fact+{stage:"RESOLUTION",step:"RESOLVE_ACTIVITY_CARDINALITY",core_decision:$receipt.decision,activity_occurrences:$receipt.occurrences}
        elif $receipt.decision=="UNKNOWN" and $receipt.claim.state=="UNKNOWN" and $receipt.occurrences==0 and $receipt.claim.reason=="ACTIVITY_NOT_FOUND" then unknown_fact("ACTIVITY_NOT_FOUND";"DECLARE_OR_WIDEN_ACTIVITY_SELECTOR")+{stage:"RESOLUTION",step:"RESOLVE_ACTIVITY_CARDINALITY",core_decision:$receipt.decision,activity_occurrences:$receipt.occurrences}
        elif $receipt.decision=="REFUTED" and $receipt.claim.state=="REFUTED" and $receipt.occurrences>1 and $receipt.claim.reason=="AMBIGUOUS_ACTIVITY_BINDING" then refuted_fact("AMBIGUOUS_ACTIVITY_BINDING";"NARROW_ACTIVITY_SELECTOR")+{stage:"RESOLUTION",step:"RESOLVE_ACTIVITY_CARDINALITY",core_decision:$receipt.decision,activity_occurrences:$receipt.occurrences}
        else refuted_fact("UNRECOGNIZED_CORE_ACTIVITY_RESOLUTION_DECISION";"RESTORE_CORE_ACTIVITY_RESOLUTION_RECEIPT")+{stage:"RESOLUTION",step:"RESOLVE_ACTIVITY_CARDINALITY",core_decision:($receipt.decision//null),activity_occurrences:($receipt.occurrences//null)} end
      end
    end;
  ({
    RELEASED_GOOO_IDENTITY:(if $core[0].core_release==expected_core and $core[0].summary.closed==12 then closed_fact else refuted_fact("RELEASED_GOOO_IDENTITY_MISMATCH";"RESTORE_PINNED_GOOO_RELEASE") end),
    LINK_OBSERVATION_IDENTITY:(if $link_release[0].identity_verified and $link_release[0].asset_verified then closed_fact else refuted_fact("LINK_OBSERVATION_IDENTITY_MISMATCH";"RESTORE_PINNED_LINK_OBSERVATION") end),
    PROMOTION_UNKNOWN_INPUT:(if $link[0].decision=="INCOMPLETE" and $link[0].promotion.state=="UNKNOWN" and $link[0].promotion.machine_readable_replay=={observed:2,required:3} and $link[0].promotion.canonical_envelope_adoption=={observed:0,required:3} then closed_fact else refuted_fact("PROMOTION_UNKNOWN_INPUT_MISMATCH";"RESTORE_OBSERVED_PROMOTION_UNKNOWN") end),
    INTERCHANGE_AUTHORITY:(if $aggregate[0].authority=={source:"GOLDEN_FIXTURES",domain_release_adoption:"NOT_CLAIMED",cross_project_required_gates:0} and $aggregate[0].schema_files==4 then closed_fact else refuted_fact("INTERCHANGE_AUTHORITY_MISMATCH";"RESTORE_INTERCHANGE_AUTHORITY") end),
    PROJECT_ENVELOPE:(if $aggregate[0].project_files==9 then closed_fact else refuted_fact("PROJECT_ENVELOPE_MISMATCH";"RESTORE_PROJECT_ENVELOPES") end),
    RELATION_ENVELOPE:(if $aggregate[0].relation_rows==9 and $aggregate[0].relation_anchors==9 then closed_fact else refuted_fact("RELATION_ENVELOPE_MISMATCH";"RESTORE_RELATION_ENVELOPES") end),
    UNKNOWN_TUPLE:(if $aggregate[0].unknown_tuples==3 and $aggregate[0].unknown_rows==3 then closed_fact else refuted_fact("UNKNOWN_TUPLE_MISMATCH";"RESTORE_UNKNOWN_TUPLES") end),
    FIVE_FILE_BUNDLES:(if $aggregate[0].bundles==9 and $aggregate[0].generated_files==45 then closed_fact else refuted_fact("FIVE_FILE_BUNDLE_MISMATCH";"RESTORE_FIVE_FILE_BUNDLES") end),
    SIX_LOCAL_CHECKS:(if $aggregate[0].local_checks_closed==54 and $aggregate[0].local_checks_total==54 then closed_fact else refuted_fact("LOCAL_CONFORMANCE_MISMATCH";"RESTORE_SIX_LOCAL_CHECKS") end),
    NINE_GOLDEN_FIXTURES:(if $aggregate[0].fixtures==9 and $aggregate[0].domains==3 and $aggregate[0].states=={MATCH:3,MISMATCH:3,UNKNOWN:3} then closed_fact else refuted_fact("GOLDEN_FIXTURE_MATRIX_MISMATCH";"RESTORE_GOLDEN_FIXTURE_MATRIX") end),
    DETERMINISTIC_REPLAY:(if $aggregate[0].replays_closed==9 and $aggregate[0].replays_total==9 then closed_fact else refuted_fact("DETERMINISTIC_REPLAY_MISMATCH";"RESTORE_DETERMINISTIC_BUNDLE_GENERATION") end),
    ZERO_EXTERNAL_GATES:(if $aggregate[0].external_required_gates==0 and $runtime[0].repository.writes==0 and $runtime[0].local_tests_run==0 then closed_fact else refuted_fact("INDEPENDENCE_CONTRACT_MISMATCH";"RESTORE_ZERO_EXTERNAL_GATES") end)
  }) as $facts |
  (reduce $d.cells[] as $cell ({cells:[],decisions:{}};
    . as $acc | (resolution($cell)) as $resolution | ([$cell.depends_on[]?|$acc.decisions[.]]) as $deps | ($facts[$cell.id]) as $fact |
    (if $resolution.state!="CLOSED" then $resolution elif any($deps[];.state=="REFUTED") then {state:"REFUTED",reason:"DEPENDENCY_REFUTED",next_operation:"RESOLVE_REFUTED_PREDECESSORS",unknown_class:null,resolution:"EXACT",blocked_by:[$deps[]|select(.state=="REFUTED")|.cell_id]} elif any($deps[];.state=="UNKNOWN") then {state:"UNKNOWN",reason:"DEPENDENCY_BLOCKED",next_operation:"RESOLVE_UNKNOWN_PREDECESSORS",unknown_class:"DEPENDENCY_BLOCKED",resolution:"PREREQUISITE_CLASS",blocked_by:[$deps[]|select(.state=="UNKNOWN")|.cell_id]} elif $fact.state!="CLOSED" then $fact else {state:"CLOSED",reason:$cell.closed_reason,next_operation:"NONE",unknown_class:null,resolution:"EXACT",blocked_by:[]} end) as $decision |
    ($decision+{cell_id:$cell.id,stage:($decision.stage//$cell.stage),step:($decision.step//$cell.step)}) as $indexed |
    .cells+=[$cell+$indexed+{core_resolution:{state:$resolution.state,decision:($resolution.core_decision//null),activity_occurrences:($resolution.activity_occurrences//null),stage:$resolution.stage,step:$resolution.step,reason:$resolution.reason,next_operation:$resolution.next_operation,unknown_class:$resolution.unknown_class}}] | .decisions[$cell.id]=$indexed)) as $evaluation |
  ([$evaluation.cells[]|select(.state=="CLOSED")]|length) as $closed | ([$evaluation.cells[]|select(.state=="UNKNOWN")]|length) as $unknown | ([$evaluation.cells[]|select(.state=="REFUTED")]|length) as $refuted |
  ([$evaluation.cells[]|select(.state!="CLOSED")][0]//null) as $first |
  {schema:"gooo/interchange/specification-report/v1",scenario:$scenario,decision:(if $refuted>0 then "FAIL_CLOSED" elif $unknown>0 then "INCOMPLETE" else "SPECIFICATION_CONFORMANT" end),
   claim:(if $first==null then {state:"CLOSED",stage:null,step:null,reason:"INTERCHANGE_SPECIFICATION_CONFORMANT",next_operation:"PUBLISH_ADVISORY_DOMAIN_ADOPTIONS",unknown_class:null,blocked_by:[]} else {state:$first.state,stage:$first.stage,step:$first.step,reason:$first.reason,next_operation:$first.next_operation,unknown_class:$first.unknown_class,blocked_by:$first.blocked_by} end),
   summary:{total:12,closed:$closed,unknown:$unknown,refuted:$refuted,domains:$aggregate[0].domains,fixtures:$aggregate[0].fixtures,bundles:$aggregate[0].bundles,generated_files:$aggregate[0].generated_files,local_checks_closed:$aggregate[0].local_checks_closed,local_checks_total:$aggregate[0].local_checks_total},
   contract:{required_files_per_bundle:5,required_local_checks_per_bundle:6,external_required_gates:0,relation_states:["MATCH","MISMATCH","UNKNOWN"],unknown_fields:["stage","step","reason","unknown_class","next_operation"]},
   adoption:{specification_fixture_conformance:{observed:$aggregate[0].fixtures,total:9},released_domain_adoption:{observed:0,total:3},connector_implementation:"NOT_STARTED"},
   authority:{link_observation_release:$link_lock[0].tag,domain_release_adoption:"NOT_CLAIMED",current_domain_branches:0,cross_project_required_gates:0},runtime:$runtime[0],
   proofs:[$d.proof_totals[] as $p|{choice:$p.proof_choice,closed:([$evaluation.cells[]|select(.proof_choice==$p.proof_choice and .state=="CLOSED")]|length),total:$p.total}],
   indicator_classes:[$d.indicator_totals[] as $i|{class:$i.indicator_class,closed:([$evaluation.cells[]|select(.indicator_class==$i.indicator_class and .state=="CLOSED")]|length),total:$i.total}],cells:$evaluation.cells}
' > "$output"
