#!/usr/bin/env bash
set -euo pipefail

if test "$#" -ne 9; then
  echo "usage: evaluate-released-domain-consumer-kit-v2.sh GRAPH CORE DENOMINATOR RELEASE KIT ENVELOPES RUNTIME OUTPUT SCENARIO" >&2
  exit 64
fi

graph=$1
core=$2
denominator=$3
release=$4
kit=$5
envelopes=$6
runtime=$7
output=$8
scenario=$9
for file in "$graph" "$core" "$denominator" "$release" "$kit" "$envelopes" "$runtime"; do
  test -f "$file" || exit 66
done

jq -S -n \
  --slurpfile graph "$graph" \
  --slurpfile core "$core" \
  --slurpfile denominator "$denominator" \
  --slurpfile release "$release" \
  --slurpfile kit "$kit" \
  --slurpfile envelopes "$envelopes" \
  --slurpfile runtime "$runtime" \
  --arg scenario "$scenario" '
  ($denominator[0]) as $d |
  def closed_fact: {state:"CLOSED",reason:"FACT_OBSERVED",next_operation:"NONE",unknown_class:null,blocked_by:[]};
  def unknown_fact($reason;$next): {state:"UNKNOWN",reason:$reason,next_operation:$next,unknown_class:"DIRECT_MISSING",blocked_by:[]};
  def refuted_fact($reason;$next): {state:"REFUTED",reason:$reason,next_operation:$next,unknown_class:null,blocked_by:[]};
  def core_resolution($cell):
    ([$core[0].receipts[]?|select(.selector.name?==$cell.activity)]) as $receipts |
    if ($receipts|length)==0 then
      unknown_fact("CORE_ACTIVITY_RESOLUTION_RECEIPT_UNAVAILABLE";"PROVIDE_CORE_ACTIVITY_RESOLUTION_RECEIPT")+
      {stage:"RESOLUTION",step:"RESOLVE_ACTIVITY_CARDINALITY"}
    elif ($receipts|length)>1 then
      refuted_fact("DUPLICATE_CORE_ACTIVITY_RESOLUTION_RECEIPT";"REMOVE_DUPLICATE_CORE_ACTIVITY_RESOLUTION_RECEIPT")+
      {stage:"RESOLUTION",step:"RESOLVE_ACTIVITY_CARDINALITY"}
    else
      ($receipts[0]) as $r |
      if $r.decision=="CLOSED" and $r.claim.state=="CLOSED" and $r.occurrences==1 and $r.claim.reason=="ACTIVITY_UNIQUELY_RESOLVED" then
        closed_fact+{stage:"RESOLUTION",step:"RESOLVE_ACTIVITY_CARDINALITY",core_decision:$r.decision}
      elif $r.decision=="UNKNOWN" and $r.claim.state=="UNKNOWN" and $r.occurrences==0 and $r.claim.reason=="ACTIVITY_NOT_FOUND" then
        unknown_fact("ACTIVITY_NOT_FOUND";"DECLARE_OR_WIDEN_ACTIVITY_SELECTOR")+
        {stage:"RESOLUTION",step:"RESOLVE_ACTIVITY_CARDINALITY",core_decision:$r.decision}
      elif $r.decision=="REFUTED" and $r.claim.state=="REFUTED" and $r.occurrences>1 and $r.claim.reason=="AMBIGUOUS_ACTIVITY_BINDING" then
        refuted_fact("AMBIGUOUS_ACTIVITY_BINDING";"NARROW_ACTIVITY_SELECTOR")+
        {stage:"RESOLUTION",step:"RESOLVE_ACTIVITY_CARDINALITY",core_decision:$r.decision}
      else
        refuted_fact("UNRECOGNIZED_CORE_ACTIVITY_RESOLUTION_DECISION";"RESTORE_CORE_ACTIVITY_RESOLUTION_RECEIPT")+
        {stage:"RESOLUTION",step:"RESOLVE_ACTIVITY_CARDINALITY",core_decision:($r.decision//null)}
      end
    end;
  ({
    SPEC_RELEASE:
      (if $release[0].available!=true then
         unknown_fact("RELEASED_SPECIFICATION_UNAVAILABLE";"RESTORE_PINNED_SPECIFICATION_RELEASE")
       elif $release[0].verified==true and $release[0].assets_verified==3 then
         closed_fact
       else
         refuted_fact("RELEASED_SPECIFICATION_MISMATCH";"RESTORE_PINNED_SPECIFICATION_RELEASE")
       end),
    RELEASED_PROJECTION:
      (if $release[0].report_decision=="SPECIFICATION_PROJECTION_CONFORMANT" and $release[0].report_cells==12 then closed_fact
       else refuted_fact("RELEASED_PROJECTION_EVIDENCE_MISMATCH";"RESTORE_RELEASED_PROJECTION_EVIDENCE") end),
    SIX_SCHEMAS:
      (if $kit[0].schemas==6 then closed_fact
       else refuted_fact("ENVELOPE_SCHEMA_CARDINALITY_MISMATCH";"RESTORE_SIX_ENVELOPE_SCHEMAS") end),
    READ_ONLY_CONFORMER:
      (if $kit[0].conformers==1 and $kit[0].read_only==true then closed_fact
       else refuted_fact("READ_ONLY_CONFORMER_MISMATCH";"RESTORE_READ_ONLY_CONFORMER") end),
    ELEVEN_FILE_KIT:
      (if $kit[0].files==11 then closed_fact
       else refuted_fact("CONSUMER_KIT_FILE_SET_MISMATCH";"RESTORE_ELEVEN_FILE_CONSUMER_KIT") end),
    INTERNAL_CHECKSUMS:
      (if $kit[0].checksum_entries==10 and $kit[0].checksums_verified==10 then closed_fact
       else refuted_fact("INTERNAL_CHECKSUM_MISMATCH";"RESTORE_INTERNAL_CHECKSUMS") end),
    THREE_RELEASED_ENVELOPES:
      (if $envelopes[0].envelopes==3 and $envelopes[0].checks_closed==30 and $envelopes[0].checks_total==30 then closed_fact
       else refuted_fact("RELEASED_ENVELOPE_CONFORMANCE_MISMATCH";"RESTORE_RELEASED_ENVELOPE_CONFORMANCE") end),
    DETERMINISTIC_ARCHIVE:
      (if $kit[0].archive_replays==1 and $kit[0].archive_replays_equal==1 then closed_fact
       else refuted_fact("NONDETERMINISTIC_CONSUMER_KIT_ARCHIVE";"RESTORE_DETERMINISTIC_ARCHIVE") end),
    SIX_UNKNOWN_COORDINATES:
      (if $envelopes[0].valid_unknown_cases==1 and $envelopes[0].unknown_coordinate_fields==6 then closed_fact
       else refuted_fact("UNKNOWN_COORDINATE_TUPLE_INCOMPLETE";"RESTORE_SIX_UNKNOWN_COORDINATES") end),
    NO_PRODUCT_GENERATOR:
      (if $kit[0].generators==0 and $runtime[0].product_generation_authorized==false then closed_fact
       else refuted_fact("PRODUCT_GENERATOR_INCLUDED";"REMOVE_PRODUCT_GENERATOR") end),
    NO_AUTHORITY_ESCALATION:
      (if $runtime[0].repository_writes==0 and $runtime[0].local_tests_run==0 and
          $runtime[0].cross_project_required_gates==0 and $runtime[0].product_generation_authorized==false then closed_fact
       else refuted_fact("READ_ONLY_AUTHORITY_ESCALATED";"REMOVE_WRITE_OR_GENERATION_AUTHORITY") end),
    INDEPENDENT_CONSUMPTION:
      (if $kit[0].repository_checkout_required==false and $kit[0].generators==0 and
          $runtime[0].domain_release_adoption_claimed==false then closed_fact
       else refuted_fact("CONSUMPTION_REQUIRES_SOURCE_OR_GENERATOR_AUTHORITY";"REMOVE_SOURCE_CHECKOUT_OR_GENERATOR_REQUIREMENT") end)
  }) as $facts |
  (reduce $d.cells[] as $cell ({cells:[],decisions:{}};
    . as $acc |
    (core_resolution($cell)) as $resolution |
    ([$cell.depends_on[]?|$acc.decisions[.]]) as $deps |
    ($facts[$cell.id]) as $fact |
    (if $resolution.state!="CLOSED" then $resolution
     elif any($deps[];.state=="REFUTED") then
       refuted_fact("DEPENDENCY_REFUTED";"RESOLVE_REFUTED_PREDECESSORS")+
       {blocked_by:[$deps[]|select(.state=="REFUTED")|.cell_id]}
     elif any($deps[];.state=="UNKNOWN") then
       unknown_fact("DEPENDENCY_BLOCKED";"RESOLVE_UNKNOWN_PREDECESSORS")+
       {unknown_class:"DEPENDENCY_BLOCKED",blocked_by:[$deps[]|select(.state=="UNKNOWN")|.cell_id]}
     elif $fact.state!="CLOSED" then $fact
     else {state:"CLOSED",reason:$cell.closed_reason,next_operation:"NONE",unknown_class:null,blocked_by:[]}
     end) as $decision |
    ($decision+{cell_id:$cell.id,stage:($decision.stage//$cell.stage),step:($decision.step//$cell.step)}) as $indexed |
    .cells+=[$cell+$indexed+{core_resolution:{state:$resolution.state,decision:($resolution.core_decision//null),reason:$resolution.reason}}] |
    .decisions[$cell.id]=$indexed
  )) as $evaluation |
  ([$evaluation.cells[]|select(.state=="CLOSED")]|length) as $closed |
  ([$evaluation.cells[]|select(.state=="UNKNOWN")]|length) as $unknown |
  ([$evaluation.cells[]|select(.state=="REFUTED")]|length) as $refuted |
  ([$evaluation.cells[]|select(.state!="CLOSED")][0]//null) as $first |
  {
    schema:"gooo/interchange/released-domain-consumer-kit-report/v2",
    scenario:$scenario,
    decision:(if $refuted>0 then "FAIL_CLOSED" elif $unknown>0 then "INCOMPLETE" else "CONSUMER_KIT_CONFORMANT" end),
    claim:(if $first==null then
      {state:"CLOSED",stage:null,step:null,reason:"RELEASED_DOMAIN_CONSUMER_KIT_CONFORMANT",unknown_class:null,next_operation:"PUBLISH_RELEASED_CONSUMER_KIT",blocked_by:[]}
    else
      {state:$first.state,stage:$first.stage,step:$first.step,reason:$first.reason,unknown_class:$first.unknown_class,next_operation:$first.next_operation,blocked_by:$first.blocked_by}
    end),
    summary:{
      total_cells:12,closed_cells:$closed,unknown_cells:$unknown,refuted_cells:$refuted,
      kit_files:$kit[0].files,schemas:$kit[0].schemas,conformers:$kit[0].conformers,generators:$kit[0].generators,
      checksum_entries:$kit[0].checksum_entries,checksums_verified:$kit[0].checksums_verified,
      released_envelopes:$envelopes[0].envelopes,checks_closed:$envelopes[0].checks_closed,checks_total:$envelopes[0].checks_total,
      valid_unknown_cases:$envelopes[0].valid_unknown_cases,unknown_coordinate_fields:$envelopes[0].unknown_coordinate_fields
    },
    adoption:{released_domain_adoption:{observed:0,total:3},connector_implementation:"NOT_STARTED"},
    utility:{state:"UNKNOWN",evidence:{observed:0,total:1}},
    improvement:{state:"UNKNOWN",exact_before_after_pairs:{observed:0,total:1}},
    authority:{
      read_only:true,repository_writes:$runtime[0].repository_writes,local_tests_run:$runtime[0].local_tests_run,
      product_generation_authorized:$runtime[0].product_generation_authorized,
      cross_project_required_gates:$runtime[0].cross_project_required_gates,
      domain_release_adoption_claimed:$runtime[0].domain_release_adoption_claimed
    },
    proofs:[$d.proof_totals[] as $p|{choice:$p.proof_choice,closed:([$evaluation.cells[]|select(.proof_choice==$p.proof_choice and .state=="CLOSED")]|length),total:$p.total}],
    indicator_classes:[$d.indicator_totals[] as $i|{class:$i.indicator_class,closed:([$evaluation.cells[]|select(.indicator_class==$i.indicator_class and .state=="CLOSED")]|length),total:$i.total}],
    runtime:$runtime[0],
    cells:$evaluation.cells
  }
' > "$output"
