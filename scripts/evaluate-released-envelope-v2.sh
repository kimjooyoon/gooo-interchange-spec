#!/usr/bin/env bash
set -euo pipefail

if test "$#" -ne 10; then
  echo "usage: evaluate-released-envelope-v2.sh GRAPH CORE DENOMINATOR LOCK RELEASES AGGREGATE COUNTEREXAMPLES RUNTIME OUTPUT SCENARIO" >&2
  exit 64
fi
graph=$1; core=$2; denominator=$3; lock=$4; releases=$5; aggregate=$6; counterexamples=$7; runtime=$8; output=$9
shift 9
scenario=$1
for file in "$graph" "$core" "$denominator" "$lock" "$releases" "$aggregate" "$counterexamples" "$runtime"; do test -f "$file" || exit 66; done

jq -S -n --slurpfile graph "$graph" --slurpfile core "$core" --slurpfile denominator "$denominator" --slurpfile lock "$lock" \
  --slurpfile releases "$releases" --slurpfile aggregate "$aggregate" --slurpfile counterexamples "$counterexamples" --slurpfile runtime "$runtime" --arg scenario "$scenario" '
  ($denominator[0]) as $d |
  def closed_fact: {state:"CLOSED",reason:"FACT_OBSERVED",next_operation:"NONE",unknown_class:null,blocked_by:[]};
  def unknown_fact($reason;$next): {state:"UNKNOWN",reason:$reason,next_operation:$next,unknown_class:"DIRECT_MISSING",blocked_by:[]};
  def refuted_fact($reason;$next): {state:"REFUTED",reason:$reason,next_operation:$next,unknown_class:null,blocked_by:[]};
  def core_resolution($cell):
    ([$core[0].receipts[]?|select(.selector.name?==$cell.activity)]) as $receipts |
    if ($receipts|length)==0 then unknown_fact("CORE_ACTIVITY_RESOLUTION_RECEIPT_UNAVAILABLE";"PROVIDE_CORE_ACTIVITY_RESOLUTION_RECEIPT")+{stage:"RESOLUTION",step:"RESOLVE_ACTIVITY_CARDINALITY"}
    elif ($receipts|length)>1 then refuted_fact("DUPLICATE_CORE_ACTIVITY_RESOLUTION_RECEIPT";"REMOVE_DUPLICATE_CORE_ACTIVITY_RESOLUTION_RECEIPT")+{stage:"RESOLUTION",step:"RESOLVE_ACTIVITY_CARDINALITY"}
    else ($receipts[0]) as $r |
      if $r.decision=="CLOSED" and $r.claim.state=="CLOSED" and $r.occurrences==1 and $r.claim.reason=="ACTIVITY_UNIQUELY_RESOLVED" then closed_fact+{stage:"RESOLUTION",step:"RESOLVE_ACTIVITY_CARDINALITY",core_decision:$r.decision}
      elif $r.decision=="UNKNOWN" and $r.claim.state=="UNKNOWN" and $r.occurrences==0 and $r.claim.reason=="ACTIVITY_NOT_FOUND" then unknown_fact("ACTIVITY_NOT_FOUND";"DECLARE_OR_WIDEN_ACTIVITY_SELECTOR")+{stage:"RESOLUTION",step:"RESOLVE_ACTIVITY_CARDINALITY",core_decision:$r.decision}
      elif $r.decision=="REFUTED" and $r.claim.state=="REFUTED" and $r.occurrences>1 and $r.claim.reason=="AMBIGUOUS_ACTIVITY_BINDING" then refuted_fact("AMBIGUOUS_ACTIVITY_BINDING";"NARROW_ACTIVITY_SELECTOR")+{stage:"RESOLUTION",step:"RESOLVE_ACTIVITY_CARDINALITY",core_decision:$r.decision}
      else refuted_fact("UNRECOGNIZED_CORE_ACTIVITY_RESOLUTION_DECISION";"RESTORE_CORE_ACTIVITY_RESOLUTION_RECEIPT")+{stage:"RESOLUTION",step:"RESOLVE_ACTIVITY_CARDINALITY",core_decision:($r.decision//null)} end
    end;
  ({
    CORE_RELEASE:(if $releases[0].core.verified and $core[0].summary.closed==12 then closed_fact else refuted_fact("CURRENT_CORE_RELEASE_MISMATCH";"RESTORE_PINNED_CORE_RELEASE") end),
    LOCAL_RELEASE:(if $releases[0].products["local-ledger"].release_verified and $releases[0].products["local-ledger"].assets_verified==2 then closed_fact else unknown_fact("LOCAL_PRODUCT_RELEASE_UNAVAILABLE";"RESTORE_LOCAL_PRODUCT_RELEASE") end),
    DESIGN_RELEASE:(if $releases[0].products["design-evidence"].release_verified and $releases[0].products["design-evidence"].assets_verified==1 then closed_fact else unknown_fact("DESIGN_PRODUCT_RELEASE_UNAVAILABLE";"RESTORE_DESIGN_PRODUCT_RELEASE") end),
    INFRA_RELEASE:(if $releases[0].products["infra-evidence"].release_verified and $releases[0].products["infra-evidence"].assets_verified==2 then closed_fact else unknown_fact("INFRA_PRODUCT_RELEASE_UNAVAILABLE";"RESTORE_INFRA_PRODUCT_RELEASE") end),
    DOMAIN_RELATION:(if $aggregate[0].products==3 and $aggregate[0].relations==20 then closed_fact else refuted_fact("DOMAIN_RELATION_CARDINALITY_MISMATCH";"RESTORE_TWENTY_DOMAIN_RELATIONS") end),
    EVIDENCE_ANCHOR:(if $aggregate[0].evidence==20 and $aggregate[0].local_checks_closed==$aggregate[0].local_checks_total then closed_fact else refuted_fact("RELEASED_EVIDENCE_MISMATCH";"RESTORE_RELEASED_EVIDENCE_ANCHORS") end),
    CLAIM_RESOLUTION:(if $aggregate[0].resolutions==20 and $aggregate[0].normal_unknowns==0 then closed_fact else refuted_fact("CLAIM_RESOLUTION_MISMATCH";"RESTORE_CLAIM_RESOLUTIONS") end),
    EIGHT_FILE_ENVELOPE:(if $aggregate[0].envelopes==3 and $aggregate[0].files==24 then closed_fact else refuted_fact("EIGHT_FILE_ENVELOPE_MISMATCH";"RESTORE_EIGHT_FILE_ENVELOPES") end),
    UNKNOWN_COORDINATES:(if $aggregate[0].valid_unknown_cases==1 and $aggregate[0].unknown_coordinate_fields==6 then closed_fact else refuted_fact("UNKNOWN_COORDINATE_TUPLE_INCOMPLETE";"RESTORE_SIX_UNKNOWN_COORDINATES") end),
    DETERMINISTIC_REPLAY:(if $aggregate[0].source_replay_receipts==3 and $aggregate[0].source_replay_comparisons_satisfied==19 and $aggregate[0].source_replay_comparisons_total==19 and $aggregate[0].projection_replays==3 then closed_fact else refuted_fact("MACHINE_READABLE_REPLAY_MISMATCH";"RESTORE_MACHINE_READABLE_REPLAY") end),
    INVALID_ENVELOPE_REFUTATION:(if $counterexamples[0].total==5 and $counterexamples[0].fail_closed==5 then closed_fact else refuted_fact("INVALID_ENVELOPE_ACCEPTED";"RESTORE_FAIL_CLOSED_COUNTEREXAMPLES") end),
    READ_ONLY_AUTHORITY:(if $runtime[0].repository_writes==0 and $runtime[0].local_tests_run==0 and $runtime[0].cross_project_required_gates==0 and $runtime[0].product_generation_authorized==false and $runtime[0].domain_release_adoption_claimed==false then closed_fact else refuted_fact("READ_ONLY_AUTHORITY_ESCALATED";"REMOVE_WRITE_OR_GENERATION_AUTHORITY") end)
  }) as $facts |
  (reduce $d.cells[] as $cell ({cells:[],decisions:{}};
    . as $acc | (core_resolution($cell)) as $resolution | ([$cell.depends_on[]?|$acc.decisions[.]]) as $deps | ($facts[$cell.id]) as $fact |
    (if $resolution.state!="CLOSED" then $resolution
     elif any($deps[];.state=="REFUTED") then refuted_fact("DEPENDENCY_REFUTED";"RESOLVE_REFUTED_PREDECESSORS")+{blocked_by:[$deps[]|select(.state=="REFUTED")|.cell_id]}
     elif any($deps[];.state=="UNKNOWN") then unknown_fact("DEPENDENCY_BLOCKED";"RESOLVE_UNKNOWN_PREDECESSORS")+{unknown_class:"DEPENDENCY_BLOCKED",blocked_by:[$deps[]|select(.state=="UNKNOWN")|.cell_id]}
     elif $fact.state!="CLOSED" then $fact
     else {state:"CLOSED",reason:$cell.closed_reason,next_operation:"NONE",unknown_class:null,blocked_by:[]} end) as $decision |
    ($decision+{cell_id:$cell.id,stage:($decision.stage//$cell.stage),step:($decision.step//$cell.step)}) as $indexed |
    .cells+=[$cell+$indexed+{core_resolution:{state:$resolution.state,decision:($resolution.core_decision//null),reason:$resolution.reason}}] | .decisions[$cell.id]=$indexed)) as $evaluation |
  ([$evaluation.cells[]|select(.state=="CLOSED")]|length) as $closed | ([$evaluation.cells[]|select(.state=="UNKNOWN")]|length) as $unknown | ([$evaluation.cells[]|select(.state=="REFUTED")]|length) as $refuted |
  ([$evaluation.cells[]|select(.state!="CLOSED")][0]//null) as $first |
  {schema:"gooo/interchange/released-domain-envelope-report/v2",scenario:$scenario,decision:(if $refuted>0 then "FAIL_CLOSED" elif $unknown>0 then "INCOMPLETE" else "SPECIFICATION_PROJECTION_CONFORMANT" end),claim:(if $first==null then {state:"CLOSED",stage:null,step:null,reason:"RELEASED_DOMAIN_ENVELOPE_PROJECTION_CONFORMANT",unknown_class:null,next_operation:"PUBLISH_OPTIONAL_PRODUCT_OWNED_V2_ENVELOPES",blocked_by:[]} else {state:$first.state,stage:$first.stage,step:$first.step,reason:$first.reason,unknown_class:$first.unknown_class,next_operation:$first.next_operation,blocked_by:$first.blocked_by} end),summary:{total_cells:12,closed_cells:$closed,unknown_cells:$unknown,refuted_cells:$refuted,products:$aggregate[0].products,envelopes:$aggregate[0].envelopes,files:$aggregate[0].files,relations:$aggregate[0].relations,evidence:$aggregate[0].evidence,resolutions:$aggregate[0].resolutions,source_replay_receipts:$aggregate[0].source_replay_receipts,source_replay_comparisons_satisfied:$aggregate[0].source_replay_comparisons_satisfied,source_replay_comparisons_total:$aggregate[0].source_replay_comparisons_total,valid_unknown_cases:$aggregate[0].valid_unknown_cases,refuted_counterexamples:$counterexamples[0].fail_closed},adoption:{specification_owned_projections:{observed:3,total:3},released_domain_adoption:{observed:0,total:3},connector_implementation:"NOT_STARTED"},authority:{projection_owner:"INTERCHANGE_SPECIFICATION",domain_release_adoption_claimed:false,product_generation_authorized:false,central_orchestration_authorized:false,cross_project_required_gates:0},proofs:[$d.proof_totals[] as $p|{choice:$p.proof_choice,closed:([$evaluation.cells[]|select(.proof_choice==$p.proof_choice and .state=="CLOSED")]|length),total:$p.total}],indicator_classes:[$d.indicator_totals[] as $i|{class:$i.indicator_class,closed:([$evaluation.cells[]|select(.indicator_class==$i.indicator_class and .state=="CLOSED")]|length),total:$i.total}],runtime:$runtime[0],cells:$evaluation.cells}
' > "$output"
